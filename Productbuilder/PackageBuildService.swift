import Foundation
import Darwin
#if canImport(AppKit)
import AppKit
#endif

struct PackageBuildService {
    private static let defaultHostArchitectures = "arm64,x86_64"

    struct BuildResult {
        let outputURL: URL
        let uninstallerURL: URL?
    }

    func build(project: PackageProject, log: @escaping @MainActor (String) -> Void) async throws -> BuildResult {
        try await runStage("Check project settings and resources", log: log) {
            try await validate(project)
        }

        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Productbuilder-\(UUID().uuidString)", isDirectory: true)
        let componentDirectory = temporaryRoot.appendingPathComponent("Components", isDirectory: true)
        let stageDirectory = temporaryRoot.appendingPathComponent("Stage", isDirectory: true)
        try await runStage("Prepare build workspace", log: log) {
            try fileManager.createDirectory(at: componentDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: stageDirectory, withIntermediateDirectories: true)
        }

        defer {
            try? fileManager.removeItem(at: temporaryRoot)
        }

        await log("Preparing build workspace: \(temporaryRoot.path)")

        let builtComponents = try await runStage("Create component packages (\(project.components.count))", log: log) {
            var builtComponents: [BuiltComponent] = []
            for component in project.components {
                await log("Building component: \(component.name)")
                let built = try await buildComponent(
                    component,
                    componentDirectory: componentDirectory,
                    stageDirectory: stageDirectory,
                    log: log
                )
                builtComponents.append(built)
            }
            return builtComponents
        }

        let resourceManifest: ResourceManifest
        if hasInstallerResources(project) {
            resourceManifest = try await runStage("Prepare installer resources", log: log) {
                try await makeResourcesDirectory(project: project, baseDirectory: temporaryRoot, log: log)
            }
        } else {
            await logSkip("Prepare installer resources: none configured", log: log)
            resourceManifest = ResourceManifest()
        }

        let distributionURL = temporaryRoot.appendingPathComponent("Distribution.xml")
        try await runStage("Create Distribution XML", log: log) {
            try makeDistribution(project: project, components: builtComponents, resources: resourceManifest)
                .write(to: distributionURL, atomically: true, encoding: .utf8)
        }

        try await runStage("Clear quarantine attributes", log: log) {
            try clearQuarantineAttributes(at: temporaryRoot)
        }

        let outputDirectory = URL(fileURLWithPath: project.outputDirectory, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent(project.outputFileName)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        var arguments = [
            "--distribution", distributionURL.path,
            "--package-path", componentDirectory.path
        ]

        if let resourcesURL = resourceManifest.resourcesURL {
            arguments += ["--resources", resourcesURL.path]
        }

        arguments.append(outputURL.path)
        let productStage = project.signingIdentity.trimmed.isEmpty
            ? "Create product package"
            : "Create and sign product package"
        try await runStage(productStage, log: log) {
            try await run("/usr/bin/productbuild", arguments: arguments, log: log)
            try await rewriteProductDistributionInPackagesStyle(
                packageURL: outputURL,
                workspaceDirectory: temporaryRoot,
                log: log
            )
            await applyPackageIconIfNeeded(project: project, outputURL: outputURL, log: log)
            if !project.signingIdentity.trimmed.isEmpty {
                try await signProductPackage(
                    at: outputURL,
                    identity: project.signingIdentity.trimmed,
                    workspaceDirectory: temporaryRoot,
                    log: log
                )
            }
        }
        if project.signingIdentity.trimmed.isEmpty {
            await logSkip("Sign product package: no signing identity selected", log: log)
        }

        if project.enableNotarization {
            try await runStage("Notarize product package", log: log) {
                try await run(
                    "/usr/bin/xcrun",
                    arguments: [
                        "notarytool",
                        "submit",
                        outputURL.path,
                        "--keychain-profile",
                        project.notarizationProfile.trimmed,
                        "--wait"
                    ],
                    log: log
                )
            }

            try await runStage("Staple notarization ticket", log: log) {
                try await run(
                    "/usr/bin/xcrun",
                    arguments: [
                        "stapler",
                        "staple",
                        outputURL.path
                    ],
                    log: log
                )
            }
        } else {
            await logSkip("Notarize product package: disabled", log: log)
        }

        await log("Product package: \(outputURL.path)")

        let uninstallerURL: URL?
        if project.generateUninstaller {
            uninstallerURL = try await runStage("Create uninstaller script", log: log) {
                try makeUninstaller(project: project, components: builtComponents, outputDirectory: outputDirectory)
            }
            await log("Uninstaller script: \(uninstallerURL?.path ?? "")")
        } else {
            await logSkip("Create uninstaller script: disabled", log: log)
            uninstallerURL = nil
        }

        return BuildResult(outputURL: outputURL, uninstallerURL: uninstallerURL)
    }

    private func runStage<T>(
        _ title: String,
        log: @escaping @MainActor (String) -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        await logStage(title, log: log)
        do {
            let value = try await operation()
            await logOK(title, log: log)
            return value
        } catch {
            await logError("\(title): \(error.localizedDescription)", log: log)
            throw error
        }
    }

    private func logStage(_ message: String, log: @escaping @MainActor (String) -> Void) async {
        await log("[stage] \(message)")
    }

    private func logOK(_ message: String, log: @escaping @MainActor (String) -> Void) async {
        await log("[ok] \(message)")
    }

    private func logSkip(_ message: String, log: @escaping @MainActor (String) -> Void) async {
        await log("[skip] \(message)")
    }

    private func logError(_ message: String, log: @escaping @MainActor (String) -> Void) async {
        await log("[error] \(message)")
    }

    private func hasInstallerResources(_ project: PackageProject) -> Bool {
        ![
            project.resourcesDirectory,
            project.logoPath,
            project.backgroundPath,
            project.darkBackgroundPath,
            project.welcomePath,
            project.readmePath,
            project.licensePath,
            project.conclusionPath
        ].allSatisfy { $0.trimmed.isEmpty }
            || !project.allInstallerResourceLocalizations.allSatisfy { $0.path.trimmed.isEmpty }
    }

    private func validate(_ project: PackageProject) async throws {
        if let issue = ProjectInputValidator.validateProductName(project.productName) {
            throw BuildError.validation(issue.englishDescription(fieldName: "Product name"))
        }
        guard !project.productIdentifier.trimmed.isEmpty else {
            throw BuildError.validation("Product identifier is required.")
        }
        if let issue = ProjectInputValidator.validatePackageIdentifier(project.productIdentifier) {
            throw BuildError.validation(issue.englishDescription(fieldName: "Product identifier"))
        }
        guard !project.productVersion.trimmed.isEmpty else {
            throw BuildError.validation("Product version is required.")
        }
        if let issue = ProjectInputValidator.validateMinimumMacOSVersion(project.minimumSystemVersion) {
            throw BuildError.validation(issue.englishDescription(fieldName: "Minimum macOS"))
        }
        if let issue = ProjectInputValidator.validateProductFileName(ProjectInputValidator.productFileNameCandidate(for: project)) {
            throw BuildError.validation(issue.englishDescription(fieldName: "Product file name"))
        }
        if project.enableNotarization {
            guard !project.signingIdentity.trimmed.isEmpty else {
                throw BuildError.validation("Notarization requires a signing identity.")
            }
            guard !project.notarizationProfile.trimmed.isEmpty else {
                throw BuildError.validation("Notarization keychain profile is required.")
            }
        }
        guard !project.outputDirectory.trimmed.isEmpty else {
            throw BuildError.validation("Output directory is required.")
        }
        guard project.enableAnywhereDomain || project.enableCurrentUserHomeDomain || project.enableLocalSystemDomain else {
            throw BuildError.validation("Enable at least one install domain.")
        }
        guard !project.components.isEmpty else {
            throw BuildError.validation("Add at least one component.")
        }

        let resourcePaths = [
            project.resourcesDirectory,
            project.logoPath,
            project.backgroundPath,
            project.darkBackgroundPath,
            project.welcomePath,
            project.readmePath,
            project.licensePath,
            project.conclusionPath
        ]
        + project.welcomeLocalizations.map(\.path)
        + project.readmeLocalizations.map(\.path)
        + project.licenseLocalizations.map(\.path)
        + project.conclusionLocalizations.map(\.path)

        for localization in project.allInstallerResourceLocalizations where !localization.path.trimmed.isEmpty && localization.normalizedLanguageCode.isEmpty {
            throw BuildError.validation("Localization language code is required for \(localization.path).")
        }

        for path in resourcePaths.filter({ !$0.trimmed.isEmpty }) where !FileManager.default.fileExists(atPath: path) {
            throw BuildError.validation("Resource does not exist: \(path)")
        }

        let fileManager = FileManager.default
        for component in project.components {
            let payloadEntries = component.effectivePayloadEntries
            guard !payloadEntries.isEmpty else {
                throw BuildError.validation("Component '\(component.name)' needs at least one payload entry.")
            }
            for payload in payloadEntries {
                guard payload.destinationPath.hasPrefix("/") else {
                    throw BuildError.validation("Destination must be an absolute path for '\(component.name)'.")
                }
                if payload.kind != .emptyDirectory {
                    guard !payload.sourcePath.trimmed.isEmpty else {
                        throw BuildError.validation("Payload entry '\(payload.title)' needs a source path.")
                    }
                    guard fileManager.fileExists(atPath: payload.sourcePath) else {
                        throw BuildError.validation("Source does not exist: \(payload.sourcePath)")
                    }
                }
                if payload.kind == .folderContents {
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: payload.sourcePath, isDirectory: &isDirectory), isDirectory.boolValue else {
                        throw BuildError.validation("Folder Contents source must be a directory: \(payload.sourcePath)")
                    }
                }
                try validatePayloadPermissions(payload)
            }
            guard !component.packageIdentifier.trimmed.isEmpty else {
                throw BuildError.validation("Component '\(component.name)' needs a package identifier.")
            }
            if let issue = ProjectInputValidator.validatePackageIdentifier(component.packageIdentifier) {
                throw BuildError.validation(issue.englishDescription(fieldName: "Component '\(component.name)' identifier"))
            }
            if component.isRequired && !component.isSelected {
                throw BuildError.validation("Component '\(component.name)' is required and must be selected by default.")
            }
            if component.mustCloseApplications {
                let enabledItems = component.mustCloseApplicationItems.filter(\.isEnabled)
                guard !enabledItems.isEmpty else {
                    throw BuildError.validation("Component '\(component.name)' requires at least one application bundle identifier to close.")
                }
                for item in enabledItems {
                    guard !item.bundleIdentifier.trimmed.isEmpty else {
                        throw BuildError.validation("Component '\(component.name)' has an empty application bundle identifier to close.")
                    }
                    if let issue = ProjectInputValidator.validatePackageIdentifier(item.bundleIdentifier) {
                        throw BuildError.validation(issue.englishDescription(fieldName: "Application bundle identifier"))
                    }
                }
            }
        }
    }

    private func buildComponent(
        _ component: PackageComponent,
        componentDirectory: URL,
        stageDirectory: URL,
        log: @escaping @MainActor (String) -> Void
    ) async throws -> BuiltComponent {
        let fileManager = FileManager.default
        let componentStage = stageDirectory.appendingPathComponent(component.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: componentStage, withIntermediateDirectories: true)

        var installedPayloadPaths: [String] = []
        for payload in component.effectivePayloadEntries {
            let stagedPaths = try stage(payload, in: componentStage)
            installedPayloadPaths.append(contentsOf: stagedPaths)
            for stagedPath in stagedPaths {
                await log("Staged \(payload.title) -> \(stagedPath)")
            }
        }

        var arguments = [
            "--root", componentStage.path,
            "--identifier", component.packageIdentifier.trimmed,
            "--version", component.version.trimmed,
            "--install-location", "/",
            "--ownership", component.ownership.rawValue
        ]

        let scriptsStage = stageDirectory
            .appendingPathComponent("PackageScripts", isDirectory: true)
            .appendingPathComponent(component.id.uuidString, isDirectory: true)
        if let scriptsDirectory = try makeScriptsDirectory(for: component, directory: scriptsStage) {
            arguments += ["--scripts", scriptsDirectory.path]
        }

        let componentPackageURL = componentDirectory.appendingPathComponent(component.componentPackageName)
        arguments.append(componentPackageURL.path)

        try await run("/usr/bin/pkgbuild", arguments: arguments, log: log)
        try await rewriteComponentPackageInfoInPackagesStyle(
            component: component,
            packageURL: componentPackageURL,
            payloadRoot: componentStage,
            workspaceDirectory: stageDirectory,
            log: log
        )
        await log("Built component package: \(componentPackageURL.lastPathComponent)")

        return BuiltComponent(component: component, packageURL: componentPackageURL, installedPayloadPaths: installedPayloadPaths)
    }

    private func rewriteComponentPackageInfoInPackagesStyle(
        component: PackageComponent,
        packageURL: URL,
        payloadRoot: URL,
        workspaceDirectory: URL,
        log: @escaping @MainActor (String) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let expandedRoot = workspaceDirectory
            .appendingPathComponent("ExpandedComponentPackages", isDirectory: true)
            .appendingPathComponent(component.id.uuidString, isDirectory: true)

        if fileManager.fileExists(atPath: expandedRoot.path) {
            try fileManager.removeItem(at: expandedRoot)
        }
        try fileManager.createDirectory(at: expandedRoot.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await run(
            "/usr/sbin/pkgutil",
            arguments: ["--expand", packageURL.path, expandedRoot.path],
            log: log
        )

        let packageInfoURL = expandedRoot.appendingPathComponent("PackageInfo")
        let existingPackageInfo = try ExistingPackageInfo(contentsOf: packageInfoURL)
        let bundleTree = try collectBundleTree(in: payloadRoot)
        let packageInfo = makePackagesStylePackageInfo(
            component: component,
            existingPackageInfo: existingPackageInfo,
            bundleTree: bundleTree
        )
        try packageInfo.write(to: packageInfoURL, atomically: true, encoding: .utf8)

        let permissionRules = try payloadPermissionRules(for: component)
        if !permissionRules.isEmpty {
            let payloadChanges = try rewritePayloadPermissions(
                in: expandedRoot.appendingPathComponent("Payload"),
                rules: permissionRules,
                workspaceDirectory: workspaceDirectory
            )
            let bomChanges = try rewriteBomPermissions(
                in: expandedRoot.appendingPathComponent("Bom"),
                rules: permissionRules,
                workspaceDirectory: workspaceDirectory
            )
            await log("Applied custom payload permissions: \(payloadChanges) payload item(s), \(bomChanges) BOM item(s)")
        }

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }

        try await run(
            "/usr/sbin/pkgutil",
            arguments: ["--flatten", expandedRoot.path, packageURL.path],
            log: log
        )

        if bundleTree.isEmpty {
            await log("Rewrote PackageInfo in Packages style: no bundles in \(component.name)")
        } else {
            await log("Rewrote PackageInfo in Packages style: \(bundleTree.flattenedCount) bundle(s) in \(component.name)")
        }
    }

    private func rewriteProductDistributionInPackagesStyle(
        packageURL: URL,
        workspaceDirectory: URL,
        log: @escaping @MainActor (String) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let expandedRoot = workspaceDirectory.appendingPathComponent("ExpandedProduct", isDirectory: true)

        if fileManager.fileExists(atPath: expandedRoot.path) {
            try fileManager.removeItem(at: expandedRoot)
        }

        try await run(
            "/usr/sbin/pkgutil",
            arguments: ["--expand", packageURL.path, expandedRoot.path],
            log: log
        )

        let distributionURL = expandedRoot.appendingPathComponent("Distribution")
        let document = try XMLDocument(data: Data(contentsOf: distributionURL), options: [])
        guard let root = document.rootElement() else {
            throw BuildError.validation("Could not read product Distribution metadata.")
        }

        var removedMetadataElementCount = 0
        var removedPackageRefCount = 0
        var normalizedMustClosePackageRefCount = 0

        for packageRef in root.elements(forName: "pkg-ref") {
            let metadataElements = packageRef.children?
                .compactMap { $0 as? XMLElement }
                .filter(isProductbuildGeneratedMetadataElement) ?? []

            for metadataElement in metadataElements {
                metadataElement.detach()
                removedMetadataElementCount += 1
            }

            if normalizeMustClosePackageRefIfNeeded(packageRef) {
                normalizedMustClosePackageRefCount += 1
            }

            if shouldRemoveEmptyGeneratedPackageRef(packageRef) {
                packageRef.detach()
                removedPackageRefCount += 1
            }
        }

        guard removedMetadataElementCount > 0 || removedPackageRefCount > 0 || normalizedMustClosePackageRefCount > 0 else { return }

        let distributionData = document.xmlData(options: [.nodePrettyPrint])
        try distributionData.write(to: distributionURL, options: .atomic)

        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }

        try await run(
            "/usr/sbin/pkgutil",
            arguments: ["--flatten", expandedRoot.path, packageURL.path],
            log: log
        )

        await log(
            "Rewrote Distribution in Packages style: removed \(removedMetadataElementCount) generated metadata element(s), \(removedPackageRefCount) empty package reference(s), normalized \(normalizedMustClosePackageRefCount) must-close package reference(s)"
        )
    }

    private func isProductbuildGeneratedMetadataElement(_ element: XMLElement) -> Bool {
        let metadataElementNames: Set<String> = [
            "bundle-version",
            "upgrade-bundle",
            "strict-identifier",
            "relocate"
        ]
        guard let name = element.name else { return false }
        return metadataElementNames.contains(name)
    }

    private func normalizeMustClosePackageRefIfNeeded(_ element: XMLElement) -> Bool {
        let childElements = element.children?.compactMap { $0 as? XMLElement } ?? []
        guard childElements.count == 1, childElements.first?.name == "must-close" else { return false }

        let directText = element.children?
            .compactMap { child -> String? in
                guard child.kind == .text else { return nil }
                return child.stringValue
            }
            .joined()
            .trimmed ?? ""
        guard directText.isEmpty else { return false }

        let attributeNamesToRemove = (element.attributes ?? [])
            .compactMap(\.name)
            .filter { $0 != "id" }

        for attributeName in attributeNamesToRemove {
            element.removeAttribute(forName: attributeName)
        }

        return !attributeNamesToRemove.isEmpty
    }

    private func shouldRemoveEmptyGeneratedPackageRef(_ element: XMLElement) -> Bool {
        let childElements = element.children?.compactMap { $0 as? XMLElement } ?? []
        guard childElements.isEmpty else { return false }

        let directText = element.children?
            .compactMap { child -> String? in
                guard child.kind == .text else { return nil }
                return child.stringValue
            }
            .joined()
            .trimmed ?? ""

        return directText.isEmpty
    }

    private func signProductPackage(
        at packageURL: URL,
        identity: String,
        workspaceDirectory: URL,
        log: @escaping @MainActor (String) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let signedURL = workspaceDirectory.appendingPathComponent("Signed-\(packageURL.lastPathComponent)")
        if fileManager.fileExists(atPath: signedURL.path) {
            try fileManager.removeItem(at: signedURL)
        }

        try await run(
            "/usr/bin/productsign",
            arguments: ["--sign", identity, packageURL.path, signedURL.path],
            log: log
        )

        try fileManager.removeItem(at: packageURL)
        try fileManager.moveItem(at: signedURL, to: packageURL)
    }

    private func stage(_ payload: PackagePayloadEntry, in componentStage: URL) throws -> [String] {
        let fileManager = FileManager.default
        let destinationRoot = componentStage.appendingPathComponent(payload.destinationPath.dropLeadingSlash, isDirectory: true)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        switch payload.kind {
        case .emptyDirectory:
            return [payload.destinationPath.normalizedAbsolutePath]

        case .fileOrFolder:
            let sourceURL = URL(fileURLWithPath: payload.sourcePath)
            let destinationURL = destinationRoot.appendingPathComponent(sourceURL.lastPathComponent)
            try copyReplacingItem(from: sourceURL, to: destinationURL)
            return [payload.destinationPath.appendingPathComponent(sourceURL.lastPathComponent)]

        case .folderContents:
            let sourceURL = URL(fileURLWithPath: payload.sourcePath, isDirectory: true)
            let contents = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
            for sourceChild in contents {
                try copyReplacingItem(from: sourceChild, to: destinationRoot.appendingPathComponent(sourceChild.lastPathComponent))
            }
            return contents.map { payload.destinationPath.appendingPathComponent($0.lastPathComponent) }
        }
    }

    private func copyReplacingItem(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try clearQuarantineAttributes(at: destinationURL)
    }

    private func validatePayloadPermissions(_ payload: PackagePayloadEntry) throws {
        let permissions = payload.permissions
        let payloadTitle = payload.title
        guard permissions.isEnabled else { return }
        _ = try userID(for: permissions.owner, fieldName: "Owner", payloadTitle: payloadTitle)
        _ = try groupID(for: permissions.group, fieldName: "Group", payloadTitle: payloadTitle)
        if payload.isBundlePayload {
            _ = try octalPermissionMode(permissions.bundleMode, fieldName: "Bundle permissions", payloadTitle: payloadTitle)
        } else {
            _ = try octalPermissionMode(permissions.directoryMode, fieldName: "Directory permissions", payloadTitle: payloadTitle)
            _ = try octalPermissionMode(permissions.fileMode, fieldName: "File permissions", payloadTitle: payloadTitle)
        }
    }

    private func payloadPermissionRules(for component: PackageComponent) throws -> [PayloadPermissionRule] {
        try component.effectivePayloadEntries.compactMap { payload in
            guard payload.permissions.isEnabled else { return nil }

            let permissions = payload.permissions
            let directoryMode = payload.isBundlePayload
                ? try octalPermissionMode(permissions.bundleMode, fieldName: "Bundle permissions", payloadTitle: payload.title)
                : try octalPermissionMode(permissions.directoryMode, fieldName: "Directory permissions", payloadTitle: payload.title)
            let fileMode = payload.isBundlePayload
                ? directoryMode
                : try octalPermissionMode(permissions.fileMode, fieldName: "File permissions", payloadTitle: payload.title)

            return PayloadPermissionRule(
                installPath: payloadPermissionRoot(for: payload),
                ownerID: try userID(for: permissions.owner, fieldName: "Owner", payloadTitle: payload.title),
                groupID: try groupID(for: permissions.group, fieldName: "Group", payloadTitle: payload.title),
                directoryMode: directoryMode,
                fileMode: fileMode,
                recursive: payload.kind != .emptyDirectory && !payload.isBundlePayload
            )
        }
        .sorted { $0.installPath.pathComponentCount > $1.installPath.pathComponentCount }
    }

    private func payloadPermissionRoot(for payload: PackagePayloadEntry) -> String {
        let destination = payload.destinationPath.normalizedAbsolutePath
        guard payload.kind == .fileOrFolder, !payload.sourcePath.trimmed.isEmpty else {
            return destination
        }
        return destination.appendingPathComponent(URL(fileURLWithPath: payload.sourcePath).lastPathComponent)
    }

    private func userID(for value: String, fieldName: String, payloadTitle: String) throws -> Int {
        let value = value.trimmed
        guard !value.isEmpty else {
            throw BuildError.validation("\(fieldName) is required for payload entry '\(payloadTitle)'.")
        }
        if let id = Int(value), id >= 0 {
            return id
        }
        guard let passwd = getpwnam(value) else {
            throw BuildError.validation("Unknown \(fieldName.lowercased()) '\(value)' for payload entry '\(payloadTitle)'.")
        }
        return Int(passwd.pointee.pw_uid)
    }

    private func groupID(for value: String, fieldName: String, payloadTitle: String) throws -> Int {
        let value = value.trimmed
        guard !value.isEmpty else {
            throw BuildError.validation("\(fieldName) is required for payload entry '\(payloadTitle)'.")
        }
        if let id = Int(value), id >= 0 {
            return id
        }
        guard let group = getgrnam(value) else {
            throw BuildError.validation("Unknown \(fieldName.lowercased()) '\(value)' for payload entry '\(payloadTitle)'.")
        }
        return Int(group.pointee.gr_gid)
    }

    private func octalPermissionMode(_ value: String, fieldName: String, payloadTitle: String) throws -> Int {
        let value = value.trimmed
        guard (3...4).contains(value.count),
              value.allSatisfy({ "01234567".contains($0) }),
              let mode = Int(value, radix: 8),
              mode <= 0o7777
        else {
            throw BuildError.validation("\(fieldName) for payload entry '\(payloadTitle)' must be an octal mode like 775 or 644.")
        }
        return mode
    }

    private func rewritePayloadPermissions(
        in payloadURL: URL,
        rules: [PayloadPermissionRule],
        workspaceDirectory: URL
    ) throws -> Int {
        guard !rules.isEmpty else { return 0 }

        var archive = try runCapturingData("/usr/bin/gzip", arguments: ["-dc", payloadURL.path])
        var offset = 0
        var changedCount = 0

        while offset + 76 <= archive.count {
            guard asciiString(in: archive, offset: offset, length: 6) == "070707" else {
                throw BuildError.validation("Payload archive is not in the expected cpio format.")
            }

            let modeOffset = offset + 18
            let uidOffset = offset + 24
            let gidOffset = offset + 30
            let namesize = try octalField(in: archive, offset: offset + 59, length: 6)
            let filesize = try octalField(in: archive, offset: offset + 65, length: 11)
            let nameStart = offset + 76
            let nameEnd = nameStart + namesize
            guard nameEnd <= archive.count else {
                throw BuildError.validation("Payload archive contains an invalid cpio path field.")
            }

            var nameBytes = Array(archive[nameStart..<nameEnd])
            if nameBytes.last == 0 {
                nameBytes.removeLast()
            }
            let archivePath = String(decoding: nameBytes, as: UTF8.self)
            if archivePath == "TRAILER!!!" {
                break
            }

            let installPath = installPath(fromArchivePath: archivePath)
            if let rule = matchingPermissionRule(for: installPath, rules: rules) {
                let currentMode = try octalField(in: archive, offset: modeOffset, length: 6)
                let fileType = currentMode & 0o170000
                let permissions = fileType == 0o040000 ? rule.directoryMode : rule.fileMode
                try writeOctalField(fileType | permissions, in: &archive, offset: modeOffset, length: 6)
                try writeOctalField(rule.ownerID, in: &archive, offset: uidOffset, length: 6)
                try writeOctalField(rule.groupID, in: &archive, offset: gidOffset, length: 6)
                changedCount += 1
            }

            let rawNextOffset = nameEnd + filesize
            let paddedNextOffset = rawNextOffset + (rawNextOffset.isMultiple(of: 2) ? 0 : 1)
            if paddedNextOffset + 6 <= archive.count,
               asciiString(in: archive, offset: paddedNextOffset, length: 6) == "070707" {
                offset = paddedNextOffset
            } else {
                offset = rawNextOffset
            }
        }

        guard changedCount > 0 else { return 0 }

        let rawPayloadURL = workspaceDirectory.appendingPathComponent("Payload-\(UUID().uuidString).cpio")
        defer { try? FileManager.default.removeItem(at: rawPayloadURL) }
        try archive.write(to: rawPayloadURL, options: .atomic)
        let compressedPayload = try runCapturingData("/usr/bin/gzip", arguments: ["-c", rawPayloadURL.path])
        try compressedPayload.write(to: payloadURL, options: .atomic)
        return changedCount
    }

    private func rewriteBomPermissions(
        in bomURL: URL,
        rules: [PayloadPermissionRule],
        workspaceDirectory: URL
    ) throws -> Int {
        guard !rules.isEmpty else { return 0 }

        let bomText = String(
            decoding: try runCapturingData("/usr/bin/lsbom", arguments: [bomURL.path]),
            as: UTF8.self
        )
        var changedCount = 0
        let rewrittenLines = bomText.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine -> String in
            let line = String(rawLine)
            guard !line.isEmpty else { return line }

            var fields = line.components(separatedBy: "\t")
            guard fields.count >= 3 else { return line }

            let installPath = installPath(fromArchivePath: fields[0])
            guard let rule = matchingPermissionRule(for: installPath, rules: rules),
                  let currentMode = Int(fields[1], radix: 8)
            else {
                return line
            }

            let fileType = currentMode & 0o170000
            let permissions = fileType == 0o040000 ? rule.directoryMode : rule.fileMode
            fields[1] = String(fileType | permissions, radix: 8)
            fields[2] = "\(rule.ownerID)/\(rule.groupID)"
            changedCount += 1
            return fields.joined(separator: "\t")
        }

        guard changedCount > 0 else { return 0 }

        let bomInputURL = workspaceDirectory.appendingPathComponent("Bom-\(UUID().uuidString).lsbom")
        let rewrittenBomURL = workspaceDirectory.appendingPathComponent("Bom-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: bomInputURL)
            try? FileManager.default.removeItem(at: rewrittenBomURL)
        }

        try rewrittenLines.joined(separator: "\n").write(to: bomInputURL, atomically: true, encoding: .utf8)
        try runQuietly("/usr/bin/mkbom", arguments: ["-i", bomInputURL.path, rewrittenBomURL.path])
        try FileManager.default.removeItem(at: bomURL)
        try FileManager.default.moveItem(at: rewrittenBomURL, to: bomURL)
        return changedCount
    }

    private func matchingPermissionRule(for installPath: String, rules: [PayloadPermissionRule]) -> PayloadPermissionRule? {
        let installPath = installPath.normalizedAbsolutePath
        return rules.first { rule in
            installPath == rule.installPath || (rule.recursive && installPath.hasPrefix("\(rule.installPath)/"))
        }
    }

    private func installPath(fromArchivePath path: String) -> String {
        var path = path
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        if path == "." || path.isEmpty {
            return "/"
        }
        return "/\(path)".normalizedAbsolutePath
    }

    private func asciiString(in data: Data, offset: Int, length: Int) -> String? {
        guard offset >= 0, offset + length <= data.count else { return nil }
        return String(data: data[offset..<(offset + length)], encoding: .ascii)
    }

    private func octalField(in data: Data, offset: Int, length: Int) throws -> Int {
        guard let value = asciiString(in: data, offset: offset, length: length),
              let parsed = Int(value, radix: 8)
        else {
            throw BuildError.validation("Payload archive contains an invalid octal metadata field.")
        }
        return parsed
    }

    private func writeOctalField(_ value: Int, in data: inout Data, offset: Int, length: Int) throws {
        let value = String(format: "%0\(length)o", value)
        guard value.utf8.count == length else {
            throw BuildError.validation("Payload metadata value does not fit into the cpio field.")
        }
        data.replaceSubrange(offset..<(offset + length), with: value.utf8)
    }

    private func makeScriptsDirectory(for component: PackageComponent, directory scriptsDirectory: URL) throws -> URL? {
        let scripts = [
            ("preinstall", component.preinstallScriptPath.trimmed),
            ("postinstall", component.postinstallScriptPath.trimmed)
        ].filter { !$0.1.isEmpty }

        guard !scripts.isEmpty else { return nil }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)

        for (scriptName, sourcePath) in scripts {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw BuildError.validation("Script does not exist: \(sourceURL.path)")
            }
            let destinationURL = scriptsDirectory.appendingPathComponent(scriptName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try clearQuarantineAttributes(at: destinationURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        }

        return scriptsDirectory
    }

    private func makeResourcesDirectory(
        project: PackageProject,
        baseDirectory: URL,
        log: @escaping @MainActor (String) -> Void
    ) async throws -> ResourceManifest {
        let fileManager = FileManager.default
        var manifest = ResourceManifest()
        let hasExplicitScreens = ![
            project.welcomePath,
            project.readmePath,
            project.licensePath,
            project.conclusionPath
        ].allSatisfy { $0.trimmed.isEmpty }
            || !project.allInstallerResourceLocalizations.allSatisfy { $0.path.trimmed.isEmpty }
        let hasExplicitVisuals = ![
            project.logoPath,
            project.backgroundPath,
            project.darkBackgroundPath
        ].allSatisfy { $0.trimmed.isEmpty }

        guard !project.resourcesDirectory.trimmed.isEmpty || hasExplicitScreens || hasExplicitVisuals else {
            return manifest
        }

        let resourcesURL = baseDirectory.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        manifest.resourcesURL = resourcesURL

        if !project.resourcesDirectory.trimmed.isEmpty {
            let sourceDirectory = URL(fileURLWithPath: project.resourcesDirectory, isDirectory: true)
            let contents = try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
            for sourceURL in contents {
                let destinationURL = resourcesURL.appendingPathComponent(sourceURL.lastPathComponent)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            await log("Copied resources from \(sourceDirectory.path)")
        }

        manifest.logoFile = try copyVisualResource(
            project.logoPath,
            prefix: "Logo",
            to: resourcesURL
        )
        if let logoFile = manifest.logoFile {
            await log("Added package icon resource: \(logoFile)")
        }

        manifest.backgroundFile = try copyVisualResource(
            project.backgroundPath,
            prefix: "background",
            to: resourcesURL
        )
        if let backgroundFile = manifest.backgroundFile {
            await log("Added light background: \(backgroundFile)")
        }

        let darkBackgroundPath = project.darkBackgroundPath.trimmed.isEmpty
            ? project.backgroundPath
            : project.darkBackgroundPath
        manifest.darkBackgroundFile = try copyVisualResource(
            darkBackgroundPath,
            prefix: "background-darkAqua",
            to: resourcesURL
        )
        if let darkBackgroundFile = manifest.darkBackgroundFile {
            if project.darkBackgroundPath.trimmed.isEmpty {
                await log("Added dark background fallback: \(darkBackgroundFile)")
            } else {
                await log("Added dark background: \(darkBackgroundFile)")
            }
        }

        manifest.welcomeFile = try copyScreen(
            project.welcomePath,
            localizations: project.welcomeLocalizations,
            prefix: "Welcome",
            to: resourcesURL,
            log: log
        )
        manifest.readmeFile = try copyScreen(
            project.readmePath,
            localizations: project.readmeLocalizations,
            prefix: "ReadMe",
            to: resourcesURL,
            log: log
        )
        manifest.licenseFile = try copyScreen(
            project.licensePath,
            localizations: project.licenseLocalizations,
            prefix: "License",
            to: resourcesURL,
            log: log
        )
        manifest.conclusionFile = try copyScreen(
            project.conclusionPath,
            localizations: project.conclusionLocalizations,
            prefix: "Conclusion",
            to: resourcesURL,
            log: log
        )

        return manifest
    }

    private func copyScreen(
        _ path: String,
        localizations: [LocalizedInstallerResource],
        prefix: String,
        to resourcesURL: URL,
        log: @escaping @MainActor (String) -> Void
    ) throws -> String? {
        let validLocalizations = localizations.filter { !$0.path.trimmed.isEmpty && !$0.normalizedLanguageCode.isEmpty }
        guard !path.trimmed.isEmpty || !validLocalizations.isEmpty else { return nil }

        let sourceForFileName = !path.trimmed.isEmpty ? path : validLocalizations[0].path
        let fileName = screenFileName(from: sourceForFileName, prefix: prefix)
        let fileManager = FileManager.default

        for localization in validLocalizations {
            let lprojDirectory = resourcesURL.appendingPathComponent("\(localization.normalizedLanguageCode).lproj", isDirectory: true)
            try fileManager.createDirectory(at: lprojDirectory, withIntermediateDirectories: true)
            try copyItem(from: URL(fileURLWithPath: localization.path), to: lprojDirectory.appendingPathComponent(fileName))
        }

        if validLocalizations.isEmpty {
            try copyItem(from: URL(fileURLWithPath: path), to: resourcesURL.appendingPathComponent(fileName))
        }

        if !validLocalizations.isEmpty {
            Task { @MainActor in
                log("Added \(validLocalizations.count) localization(s) for \(fileName)")
            }
        }

        return fileName
    }

    private func screenFileName(from path: String, prefix: String) -> String {
        let sourceURL = URL(fileURLWithPath: path)
        let fileExtension = sourceURL.pathExtension
        return fileExtension.isEmpty ? prefix : "\(prefix).\(fileExtension)"
    }

    private func copyVisualResource(_ path: String, prefix: String, to resourcesURL: URL) throws -> String? {
        guard !path.trimmed.isEmpty else { return nil }

        let sourceURL = URL(fileURLWithPath: path)
        let fileName = screenFileName(from: path, prefix: prefix)
        try copyItem(from: sourceURL, to: resourcesURL.appendingPathComponent(fileName))
        return fileName
    }

    private func copyItem(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try clearQuarantineAttributes(at: destinationURL)
    }

    private func clearQuarantineAttributes(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-rd", "com.apple.quarantine", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BuildError.commandFailed("/usr/bin/xattr", process.terminationStatus)
        }
    }

    private func makeDistribution(
        project: PackageProject,
        components: [BuiltComponent],
        resources: ResourceManifest
    ) -> String {
        let domains = #"<domains enable_anywhere="\#(project.enableAnywhereDomain.xmlBool)" enable_currentUserHome="\#(project.enableCurrentUserHomeDomain.xmlBool)" enable_localSystem="\#(project.enableLocalSystemDomain.xmlBool)"/>"#

        let screenTags = [
            resources.welcomeFile.map { installerResourceTag("welcome", file: $0) },
            resources.readmeFile.map { installerResourceTag("readme", file: $0) },
            resources.licenseFile.map { installerResourceTag("license", file: $0) },
            resources.conclusionFile.map { installerResourceTag("conclusion", file: $0) }
        ].compactMap { $0 }.joined(separator: "\n")
        let backgroundTags = [
            resources.backgroundFile.map {
                backgroundResourceTag(
                    "background",
                    file: $0,
                    scaling: project.backgroundScaling,
                    alignment: project.backgroundAlignment
                )
            },
            resources.darkBackgroundFile.map {
                backgroundResourceTag(
                    "background-darkAqua",
                    file: $0,
                    scaling: project.backgroundScaling,
                    alignment: project.backgroundAlignment
                )
            }
        ].compactMap { $0 }.joined(separator: "\n")

        let minimumSystemRequirement: String
        if !project.minimumSystemVersion.trimmed.isEmpty {
            let minimumVersion = project.minimumSystemVersion.trimmed.xmlEscaped
            minimumSystemRequirement = """
                <allowed-os-versions>
                    <os-version min="\(minimumVersion)"/>
                </allowed-os-versions>
            """
        } else {
            minimumSystemRequirement = ""
        }

        let outlineLines = components
            .map { #"        <line choice="\#($0.choiceID)"/>"# }
            .joined(separator: "\n")

        let choices = components
            .map {
                """
                    <choice id="\($0.choiceID)" title="\($0.component.name.xmlEscaped)" selected="\($0.component.isSelected.xmlBool)" enabled="\((!$0.component.isRequired).xmlBool)" visible="\($0.component.isVisible.xmlBool)">
                        <pkg-ref id="\($0.component.packageIdentifier.xmlEscaped)"/>
                    </choice>
                """
            }
            .joined(separator: "\n")

        let packageRefs = components
            .map {
                """
                    <pkg-ref id="\($0.component.packageIdentifier.xmlEscaped)" version="\($0.component.version.xmlEscaped)" auth="Root" onConclusion="none">\($0.packageURL.lastPathComponent.xmlEscaped)</pkg-ref>
                """
            }
            .joined(separator: "\n")
        let mustClosePackageRefs = components
            .compactMap { component in
                let applicationIDs = component.component.mustCloseApplicationItems
                    .filter { component.component.mustCloseApplications && $0.isEnabled }
                    .map { $0.bundleIdentifier.trimmed }
                    .filter { !$0.isEmpty }
                    .uniqued()

                guard !applicationIDs.isEmpty else { return nil }

                let applications = applicationIDs
                    .map { #"            <app id="\#($0.xmlEscaped)"/>"# }
                    .joined(separator: "\n")

                return """
                    <pkg-ref id="\(component.component.packageIdentifier.xmlEscaped)">
                        <must-close>
                \(applications)
                        </must-close>
                    </pkg-ref>
                """
            }
            .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <installer-gui-script minSpecVersion="1">
            <title>\(project.productName.xmlEscaped)</title>
            <options hostArchitectures="\(Self.defaultHostArchitectures)" customize="\(project.allowCustomize ? "allow" : "never")" require-scripts="false"/>
            \(domains)
        \(backgroundTags)
        \(screenTags)
        \(minimumSystemRequirement)
            <choices-outline>
                <line choice="default">
        \(outlineLines)
                </line>
            </choices-outline>
            <choice id="default" title="\(project.productName.xmlEscaped)"/>
        \(choices)
        \(packageRefs)
        \(mustClosePackageRefs)
        </installer-gui-script>
        """
    }

    private func installerResourceTag(_ name: String, file: String) -> String {
        "    <\(name) file=\"\(file.xmlEscaped)\"\(resourceTypeAttributeSuffix(for: file))/>\n"
            .trimmingCharacters(in: .newlines)
    }

    private func backgroundResourceTag(
        _ name: String,
        file: String,
        scaling: InstallerBackgroundScaling,
        alignment: InstallerBackgroundAlignment
    ) -> String {
        "    <\(name) file=\"\(file.xmlEscaped)\"\(resourceTypeAttributeSuffix(for: file)) scaling=\"\(scaling.rawValue.xmlEscaped)\" alignment=\"\(alignment.rawValue.xmlEscaped)\"/>"
    }

    private func resourceTypeAttributeSuffix(for file: String) -> String {
        let fileExtension = URL(fileURLWithPath: file).pathExtension.lowercased()
        switch fileExtension {
        case "html", "htm":
            return #" mime-type="text/html""#
        case "rtf":
            return #" mime-type="text/rtf""#
        case "rtfd":
            return #" uti="com.apple.rtfd""#
        case "txt", "text":
            return #" mime-type="text/plain""#
        case "png":
            return #" mime-type="image/png""#
        case "jpg", "jpeg":
            return #" mime-type="image/jpeg""#
        case "gif":
            return #" mime-type="image/gif""#
        case "tif", "tiff":
            return #" mime-type="image/tiff""#
        case "icns":
            return #" uti="com.apple.icns""#
        default:
            return ""
        }
    }

    private func makePackagesStylePackageInfo(
        component: PackageComponent,
        existingPackageInfo: ExistingPackageInfo,
        bundleTree: [PackageBundleInfo]
    ) -> String {
        let scripts = packageInfoScripts(for: component)
        let bundleVersion = packageInfoBundleVersion(for: bundleTree)

        return """
        <pkg-info format-version="2" identifier="\(component.packageIdentifier.trimmed.xmlEscaped)" version="\(component.version.trimmed.xmlEscaped)" relocatable="false" overwrite-permissions="false" followSymLinks="false" install-location="/" auth="root">
        <payload installKBytes="\(existingPackageInfo.installKBytes.xmlEscaped)" numberOfFiles="\(existingPackageInfo.numberOfFiles.xmlEscaped)"/>
        \(scripts)\(bundleVersion)</pkg-info>
        """
    }

    private func packageInfoScripts(for component: PackageComponent) -> String {
        let hasPreinstall = !component.preinstallScriptPath.trimmed.isEmpty
        let hasPostinstall = !component.postinstallScriptPath.trimmed.isEmpty
        guard hasPreinstall || hasPostinstall else { return "" }

        var lines = ["<scripts>"]
        if hasPreinstall {
            lines.append("    <preinstall file=\"./preinstall\"/>")
        }
        if hasPostinstall {
            lines.append("    <postinstall file=\"./postinstall\"/>")
        }
        lines.append("</scripts>")
        return "\(lines.joined(separator: "\n"))\n"
    }

    private func packageInfoBundleVersion(for bundleTree: [PackageBundleInfo]) -> String {
        guard !bundleTree.isEmpty else { return "" }

        let bundles = bundleTree
            .map { packageInfoBundleXML(for: $0, parentPath: nil, indentation: "    ") }
            .joined(separator: "\n")

        return """
        <bundle-version>
        \(bundles)
        </bundle-version>
        """
        + "\n"
    }

    private func packageInfoBundleXML(
        for bundle: PackageBundleInfo,
        parentPath: String?,
        indentation: String
    ) -> String {
        let path = packageInfoBundlePath(for: bundle.relativePath, parentPath: parentPath)
        var attributes = [
            #"path="\#(path.xmlEscaped)""#
        ]

        if let shortVersion = bundle.shortVersion, !shortVersion.isEmpty {
            attributes.append(#"CFBundleShortVersionString="\#(shortVersion.xmlEscaped)""#)
        }
        if let version = bundle.version, !version.isEmpty {
            attributes.append(#"CFBundleVersion="\#(version.xmlEscaped)""#)
        }
        attributes.append(#"id="\#(bundle.identifier.xmlEscaped)""#)
        attributes.append(#"CFBundleIdentifier="\#(bundle.identifier.xmlEscaped)""#)

        let openingTag = "\(indentation)<bundle \(attributes.joined(separator: " "))"
        guard !bundle.children.isEmpty else {
            return "\(openingTag)/>"
        }

        let childXML = bundle.children
            .map { packageInfoBundleXML(for: $0, parentPath: bundle.relativePath, indentation: "\(indentation)    ") }
            .joined(separator: "\n")
        return """
        \(openingTag)>
        \(childXML)
        \(indentation)</bundle>
        """
    }

    private func packageInfoBundlePath(for relativePath: String, parentPath: String?) -> String {
        guard let parentPath else {
            return "./\(relativePath)"
        }

        if relativePath.hasPrefix("\(parentPath)/") {
            let childPath = relativePath.dropFirst(parentPath.count)
            return ".\(childPath)"
        }

        return "./\(relativePath)"
    }

    private func collectBundleTree(in payloadRoot: URL) throws -> [PackageBundleInfo] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: payloadRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            return []
        }

        var flatBundles: [FlatPackageBundleInfo] = []
        for case let url as URL in enumerator {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else { continue }

            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            guard fileManager.fileExists(atPath: infoURL.path) else { continue }
            guard let plist = try propertyListDictionary(at: infoURL) else { continue }
            guard let identifier = plist["CFBundleIdentifier"] as? String, !identifier.trimmed.isEmpty else { continue }

            flatBundles.append(FlatPackageBundleInfo(
                relativePath: relativePath(from: payloadRoot, to: url),
                identifier: identifier,
                shortVersion: plist["CFBundleShortVersionString"] as? String,
                version: plist["CFBundleVersion"] as? String
            ))
        }

        let sortedBundles = flatBundles.sorted { lhs, rhs in
            if lhs.relativePath.pathComponentCount == rhs.relativePath.pathComponentCount {
                return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
            return lhs.relativePath.pathComponentCount < rhs.relativePath.pathComponentCount
        }

        func nearestParentPath(for bundle: FlatPackageBundleInfo) -> String? {
            sortedBundles
                .filter { candidate in
                    candidate.relativePath != bundle.relativePath
                        && bundle.relativePath.hasPrefix("\(candidate.relativePath)/")
                }
                .max { lhs, rhs in
                    lhs.relativePath.count < rhs.relativePath.count
                }?
                .relativePath
        }

        func buildChildren(of parentPath: String?) -> [PackageBundleInfo] {
            sortedBundles
                .filter { nearestParentPath(for: $0) == parentPath }
                .map { bundle in
                    PackageBundleInfo(
                        relativePath: bundle.relativePath,
                        identifier: bundle.identifier,
                        shortVersion: bundle.shortVersion,
                        version: bundle.version,
                        children: buildChildren(of: bundle.relativePath)
                    )
                }
        }

        return buildChildren(of: nil)
    }

    private func propertyListDictionary(at url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return object as? [String: Any]
    }

    private func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("\(rootPath)/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func applyPackageIconIfNeeded(
        project: PackageProject,
        outputURL: URL,
        log: @escaping @MainActor (String) -> Void
    ) async {
        guard !project.logoPath.trimmed.isEmpty else { return }

        #if canImport(AppKit)
        let logoPath = project.logoPath
        let applied = await MainActor.run { () -> Bool in
            guard let image = NSImage(contentsOfFile: logoPath) else { return false }
            return NSWorkspace.shared.setIcon(image, forFile: outputURL.path, options: [])
        }

        if applied {
            await log("Applied package icon from \(logoPath)")
        } else {
            await log("Warning: could not apply package icon from \(logoPath)")
        }
        #else
        await log("Warning: package icon is not supported in this build environment.")
        #endif
    }

    private func makeUninstaller(
        project: PackageProject,
        components: [BuiltComponent],
        outputDirectory: URL
    ) throws -> URL {
        let outputURL = outputDirectory.appendingPathComponent(project.uninstallerFileName)
        let removeLines = components
            .flatMap(\.installedPayloadPaths)
            .uniqued()
            .sortedByPathDepthDescending()
            .map { "remove_path \($0.shellSingleQuoted)" }
            .joined(separator: "\n")
        let forgetLines = components
            .map { "forget_receipt \($0.component.packageIdentifier.shellSingleQuoted)" }
            .joined(separator: "\n")

        let script = """
        #!/bin/zsh
        set -euo pipefail

        if [[ ${EUID} -ne 0 ]]; then
          echo "Run this script with sudo."
          exit 1
        fi

        remove_path() {
          local target="$1"
          if [[ -z "$target" ]]; then
            return 0
          fi
          if [[ "$target" != "/" ]]; then
            target="${target%/}"
          fi
          case "$target" in
            "/"|"/Applications"|"/Library"|"/Library/Application Support"|"/System"|"/Users"|"/usr"|"/bin"|"/sbin"|"/var"|"/private"|"/etc"|"/tmp")
              echo "Skipped protected path $target"
              return 0
              ;;
          esac
          if [[ -e "$target" || -L "$target" ]]; then
            rm -rf -- "$target"
            echo "Removed $target"
          fi
        }

        forget_receipt() {
          local identifier="$1"
          if /usr/sbin/pkgutil --pkg-info "$identifier" >/dev/null 2>&1; then
            /usr/sbin/pkgutil --forget "$identifier" >/dev/null || true
            echo "Forgot $identifier"
          fi
        }

        \(removeLines)

        \(forgetLines)

        echo "Uninstall complete."
        """

        try script.write(to: outputURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outputURL.path)
        return outputURL
    }

    private func runCapturingData(_ launchPath: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self).trimmed
            if message.isEmpty {
                throw BuildError.commandFailed(launchPath, process.terminationStatus)
            }
            throw BuildError.validation(message)
        }

        return output
    }

    private func runQuietly(_ launchPath: String, arguments: [String]) throws {
        _ = try runCapturingData(launchPath, arguments: arguments)
    }

    private func run(
        _ launchPath: String,
        arguments: [String],
        log: @escaping @MainActor (String) -> Void
    ) async throws {
        await log("$ \(launchPath) \(arguments.map { $0.shellQuoted }.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let outputCollector = ProcessOutputCollector(log: log)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }

        try process.run()
        process.waitUntilExit()

        pipe.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(pipe.fileHandleForReading.readDataToEndOfFile())
        await outputCollector.flush()

        guard process.terminationStatus == 0 else {
            throw BuildError.commandFailed(launchPath, process.terminationStatus)
        }
    }
}

private struct PayloadPermissionRule {
    let installPath: String
    let ownerID: Int
    let groupID: Int
    let directoryMode: Int
    let fileMode: Int
    let recursive: Bool
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingText = ""
    private let log: @MainActor (String) -> Void

    init(log: @escaping @MainActor (String) -> Void) {
        self.log = log
    }

    func append(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        let lines: [String]
        lock.lock()
        pendingText += text
        var parts = pendingText.components(separatedBy: .newlines)
        pendingText = parts.popLast() ?? ""
        lines = parts
        lock.unlock()

        for line in lines where !line.trimmed.isEmpty {
            Task { await log(line) }
        }
    }

    @MainActor
    func flush() {
        let line: String
        lock.lock()
        line = pendingText
        pendingText = ""
        lock.unlock()

        if !line.trimmed.isEmpty {
            log(line.trimmed)
        }
    }
}

private struct BuiltComponent {
    let component: PackageComponent
    let packageURL: URL
    let installedPayloadPaths: [String]

    var choiceID: String {
        "choice-\(component.id.uuidString)"
    }
}

private struct ResourceManifest {
    var resourcesURL: URL?
    var logoFile: String?
    var backgroundFile: String?
    var darkBackgroundFile: String?
    var welcomeFile: String?
    var readmeFile: String?
    var licenseFile: String?
    var conclusionFile: String?
}

private struct ExistingPackageInfo {
    let installKBytes: String
    let numberOfFiles: String

    init(contentsOf packageInfoURL: URL) throws {
        let data = try Data(contentsOf: packageInfoURL)
        let document = try XMLDocument(data: data, options: [])
        guard let payload = document.rootElement()?.elements(forName: "payload").first else {
            throw BuildError.validation("Could not read payload metadata from PackageInfo.")
        }

        installKBytes = payload.attribute(forName: "installKBytes")?.stringValue ?? "0"
        numberOfFiles = payload.attribute(forName: "numberOfFiles")?.stringValue ?? "0"
    }
}

private struct PackageBundleInfo {
    let relativePath: String
    let identifier: String
    let shortVersion: String?
    let version: String?
    let children: [PackageBundleInfo]
}

private struct FlatPackageBundleInfo {
    let relativePath: String
    let identifier: String
    let shortVersion: String?
    let version: String?
}

enum BuildError: LocalizedError {
    case validation(String)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .commandFailed(let command, let status):
            return "\(command) failed with exit code \(status)."
        }
    }
}

private extension Array where Element == PackageBundleInfo {
    var flattenedCount: Int {
        reduce(0) { $0 + 1 + $1.children.flattenedCount }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var dropLeadingSlash: String {
        var result = self
        while result.hasPrefix("/") {
            result.removeFirst()
        }
        return result
    }

    var normalizedAbsolutePath: String {
        let pieces = split(separator: "/").map(String.init)
        return pieces.isEmpty ? "/" : "/\(pieces.joined(separator: "/"))"
    }

    var pathComponentCount: Int {
        split(separator: "/").count
    }

    func appendingPathComponent(_ component: String) -> String {
        let base = normalizedAbsolutePath
        return base == "/" ? "/\(component)" : "\(base)/\(component)"
    }

    var shellQuoted: String {
        if rangeOfCharacter(from: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) == nil {
            return self
        }
        return "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var shellSingleQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var javaScriptSingleQuotedStringEscaped: String {
        unicodeScalars.map { scalar in
            switch scalar {
            case "'":
                return #"\'"#
            case "\\":
                return "\\\\"
            case "\n":
                return #"\n"#
            case "\r":
                return #"\r"#
            case "\t":
                return #"\t"#
            case "<":
                return #"\x3C"#
            case ">":
                return #"\x3E"#
            case "]":
                return #"\x5D"#
            case "\u{2028}":
                return #"\u2028"#
            case "\u{2029}":
                return #"\u2029"#
            default:
                if scalar.value < 0x20 {
                    return String(format: "\\u%04X", scalar.value)
                }
                return String(scalar)
            }
        }
        .joined()
    }

    var shellEscapedForScript: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Sequence where Element == String {
    func sortedByPathDepthDescending() -> [String] {
        sorted {
            $0.split(separator: "/").count > $1.split(separator: "/").count
        }
    }
}

private extension Bool {
    var xmlBool: String {
        self ? "true" : "false"
    }
}

private extension PackageComponent {
    var effectivePayloadEntries: [PackagePayloadEntry] {
        if !payloadEntries.isEmpty {
            return payloadEntries
        }
        if sourcePath.trimmed.isEmpty {
            return []
        }
        return [PackagePayloadEntry(kind: .fileOrFolder, sourcePath: sourcePath, destinationPath: destinationPath)]
    }
}

private extension PackageProject {
    var allInstallerResourceLocalizations: [LocalizedInstallerResource] {
        welcomeLocalizations + readmeLocalizations + licenseLocalizations + conclusionLocalizations
    }
}

private extension LocalizedInstallerResource {
    var normalizedLanguageCode: String {
        var code = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.hasSuffix(".lproj") {
            code.removeLast(".lproj".count)
        }
        return code
    }
}
