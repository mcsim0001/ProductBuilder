import AppKit
import Foundation
import UniformTypeIdentifiers

enum ProjectDocument {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    @MainActor
    static func open(into model: PackageProjectModel) {
        let panel = NSOpenPanel()
        let delegate = ExtensionFilteringOpenPanelDelegate(allowedExtensions: ["json", "pkgproj"])
        panel.delegate = delegate
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        open(url, into: model)
    }

    @MainActor
    static func importPackagesProject(into model: PackageProjectModel) {
        let panel = NSOpenPanel()
        let delegate = ExtensionFilteringOpenPanelDelegate(allowedExtensions: ["pkgproj"])
        panel.delegate = delegate
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Packages Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try importPackagesProject(at: url, into: model)
            RecentProjectsStore.shared.record(url)
        } catch {
            model.appendLog("Import failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func save(_ model: PackageProjectModel) {
        if let url = model.projectURL {
            write(model.project, to: url, model: model)
        } else {
            saveAs(model)
        }
    }

    @MainActor
    static func saveAs(_ model: PackageProjectModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedFileName(for: model)
        panel.title = "Save Productbuilder Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(model.project, to: url, model: model)
    }

    @MainActor
    private static func write(_ project: PackageProject, to url: URL, model: PackageProjectModel) {
        do {
            let data = try encoder.encode(project)
            try data.write(to: url, options: .atomic)
            model.projectURL = url
            model.appendLog("Saved \(url.path)")
            RecentProjectsStore.shared.record(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    static func open(_ url: URL, into model: PackageProjectModel) {
        do {
            if url.pathExtension.lowercased() == "pkgproj" {
                try importPackagesProject(at: url, into: model)
            } else {
                let data = try Data(contentsOf: url)
                model.project = try JSONDecoder().decode(PackageProject.self, from: data)
                model.projectURL = url
                model.selectFirstComponentIfNeeded()
                model.log = ""
                model.appendLog("Opened \(url.path)")
            }
            RecentProjectsStore.shared.record(url)
        } catch {
            model.appendLog("Open failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func importPackagesProject(at url: URL, into model: PackageProjectModel) throws {
        let result = try PackagesProjectImporter.importProject(at: url)
        model.project = result.project
        model.projectURL = nil
        model.selectFirstComponentIfNeeded()
        model.log = ""
        model.appendLog("Imported Packages project: \(url.path)")
        for warning in result.warnings {
            model.appendLog("Import warning: \(warning)")
        }
    }

    @MainActor
    private static func suggestedFileName(for model: PackageProjectModel) -> String {
        if let url = model.projectURL {
            return url.lastPathComponent
        }

        let cleanedName = model.project.productName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = cleanedName.isEmpty ? "Productbuilder" : cleanedName
        return "\(name).json"
    }
}

struct RecentProjectEntry: Identifiable, Hashable {
    var path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }
}

@MainActor
final class RecentProjectsStore: ObservableObject {
    static let shared = RecentProjectsStore()

    @Published private(set) var entries: [RecentProjectEntry]

    private let storageKey = "Productbuilder.RecentProjects"
    private let maximumCount = 10

    private init() {
        let storedPaths = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        entries = storedPaths.map { RecentProjectEntry(path: $0) }
    }

    func record(_ url: URL) {
        let path = url.path
        var paths = entries.map(\.path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        paths = Array(paths.prefix(maximumCount))
        entries = paths.map { RecentProjectEntry(path: $0) }
        UserDefaults.standard.set(paths, forKey: storageKey)
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func remove(_ entry: RecentProjectEntry) {
        entries.removeAll { $0 == entry }
        UserDefaults.standard.set(entries.map(\.path), forKey: storageKey)
    }
}

private final class ExtensionFilteringOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    private let allowedExtensions: Set<String>

    init(allowedExtensions: [String]) {
        self.allowedExtensions = Set(allowedExtensions.map { $0.lowercased() })
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return true
        }
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
            throw NSError(
                domain: "ProductbuilderOpenPanel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Choose a supported project file."]
            )
        }
    }
}

enum PackagesProjectImporter {
    struct ImportResult {
        let project: PackageProject
        let warnings: [String]
    }

    static func importProject(at url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        let baseURL = url.deletingLastPathComponent()
        var warnings: [String] = []
        var project = PackageProject()
        let projectDictionary = root.dictionary("PROJECT") ?? [:]
        let settings = projectDictionary.dictionary("PROJECT_SETTINGS") ?? [:]
        let presentation = projectDictionary.dictionary("PROJECT_PRESENTATION") ?? [:]

        project.productName = firstLocalizedString(in: presentation.dictionary("TITLE")) ?? settings.string("NAME") ?? url.deletingPathExtension().lastPathComponent
        project.outputDirectory = resolvePath(settings.dictionary("BUILD_PATH"), baseURL: baseURL) ?? baseURL.path
        project.allowCustomize = true
        project.enableLocalSystemDomain = true
        project.enableAnywhereDomain = false
        project.enableCurrentUserHomeDomain = false

        if let backgroundSettings = presentation.dictionary("BACKGROUND") {
            applyBackgroundSettings(backgroundSettings, to: &project, baseURL: baseURL)
        }

        project.welcomeLocalizations = localizedResources(in: presentation.dictionary("INTRODUCTION"), baseURL: baseURL)
        project.readmeLocalizations = localizedResources(in: presentation.dictionary("README"), baseURL: baseURL)
        project.licenseLocalizations = localizedResources(in: presentation.dictionary("LICENSE"), baseURL: baseURL)

        if let welcome = preferredLocalizedPath(project.welcomeLocalizations) {
            project.welcomePath = welcome
        }
        if let readme = preferredLocalizedPath(project.readmeLocalizations) {
            project.readmePath = readme
        }
        if let license = preferredLocalizedPath(project.licenseLocalizations) {
            project.licensePath = license
        }
        if let minimumVersion = minimumSystemVersion(in: projectDictionary.dictionary("PROJECT_REQUIREMENTS")) {
            project.minimumSystemVersion = minimumVersion
        }

        let packageEntries = packages(in: root, projectDictionary: projectDictionary)
        var components: [PackageComponent] = []

        for (packageIndex, package) in packageEntries.enumerated() {
            let packageSettings = package.dictionary("PACKAGE_SETTINGS") ?? projectDictionary.dictionary("PACKAGE_SETTINGS") ?? [:]
            let packageName = packageSettings.string("NAME") ?? "Package \(packageIndex + 1)"
            let packageIdentifier = packageSettings.string("IDENTIFIER") ?? identifier(from: project.productIdentifier, suffix: packageName, index: packageIndex)
            let packageVersion = packageSettings.string("VERSION") ?? project.productVersion

            if packageIndex == 0 {
                project.productIdentifier = packageIdentifier
                project.productVersion = packageVersion
            }

            let scripts = package.dictionary("PACKAGE_SCRIPTS") ?? projectDictionary.dictionary("PACKAGE_SCRIPTS") ?? [:]
            let preinstall = resolvePath(scripts.dictionary("PREINSTALL_PATH"), baseURL: baseURL) ?? ""
            let postinstall = resolvePath(scripts.dictionary("POSTINSTALL_PATH"), baseURL: baseURL) ?? ""
            let mustCloseApplications = package.bool("MUST-CLOSE-APPLICATIONS", default: false)
            let mustCloseApplicationItems = mustCloseApplicationItems(in: package)

            let choices = choiceSettings(for: package.string("UUID"), presentation: presentation)
            let payloadEntries = payloadItems(in: package.dictionary("PACKAGE_FILES") ?? projectDictionary.dictionary("PACKAGE_FILES"), baseURL: baseURL)

            if payloadEntries.isEmpty {
                if let importedPackagePath = resolvePath(package.dictionary("PATH"), baseURL: baseURL) {
                    warnings.append("Imported package references are not embedded yet. Add payload manually for '\(packageName)'. Source package was \(importedPackagePath).")
                }
                components.append(PackageComponent(
                    name: packageName,
                    sourcePath: "",
                    destinationPath: "/Applications",
                    payloadEntries: [],
                    packageIdentifier: packageIdentifier,
                    version: packageVersion,
                    isRequired: false,
                    isSelected: choices.isSelected,
                    isVisible: choices.isVisible,
                    preinstallScriptPath: preinstall,
                    postinstallScriptPath: postinstall,
                    mustCloseApplications: mustCloseApplications,
                    mustCloseApplicationItems: mustCloseApplicationItems
                ))
                continue
            }

            let firstFilePayload = payloadEntries.first { $0.kind != .emptyDirectory }
            components.append(PackageComponent(
                name: packageName,
                sourcePath: firstFilePayload?.sourcePath ?? "",
                destinationPath: firstFilePayload?.destinationPath ?? "/",
                payloadEntries: payloadEntries,
                packageIdentifier: packageIdentifier,
                version: packageVersion,
                isRequired: false,
                isSelected: choices.isSelected,
                isVisible: choices.isVisible,
                preinstallScriptPath: preinstall,
                postinstallScriptPath: postinstall,
                mustCloseApplications: mustCloseApplications,
                mustCloseApplicationItems: mustCloseApplicationItems
            ))
        }

        if components.isEmpty {
            warnings.append("No payload entries were found. A placeholder component was created.")
            components = [PackageComponent(
                name: project.productName,
                sourcePath: "",
                destinationPath: "/Applications",
                payloadEntries: [],
                packageIdentifier: project.productIdentifier,
                version: project.productVersion
            )]
        }

        project.components = components
        return ImportResult(project: project, warnings: warnings)
    }

    private static func packages(in root: [String: Any], projectDictionary: [String: Any]) -> [[String: Any]] {
        if let packages = root["PACKAGES"] as? [[String: Any]], !packages.isEmpty {
            return packages
        }
        return [projectDictionary]
    }

    private static func mustCloseApplicationItems(in package: [String: Any]) -> [MustCloseApplicationItem] {
        guard let items = package["MUST-CLOSE-APPLICATION-ITEMS"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let bundleIdentifier = item.string("APPLICATION_ID")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleIdentifier.isEmpty else {
                return nil
            }
            return MustCloseApplicationItem(
                isEnabled: item.bool("STATE", default: true),
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    private static func firstLocalizedString(in dictionary: [String: Any]?) -> String? {
        guard let localizations = dictionary?["LOCALIZATIONS"] as? [[String: Any]] else {
            return nil
        }
        return localizations.first { $0.string("LANGUAGE") == "English" }?.string("VALUE")
            ?? localizations.compactMap { $0.string("VALUE") }.first
    }

    private static func localizedResources(in dictionary: [String: Any]?, baseURL: URL) -> [LocalizedInstallerResource] {
        guard let localizations = dictionary?["LOCALIZATIONS"] as? [[String: Any]] else {
            return []
        }
        return localizations.compactMap { localization in
            if let pathDictionary = localization.dictionary("VALUE"),
               let path = resolvePath(pathDictionary, baseURL: baseURL) {
                return LocalizedInstallerResource(
                    languageCode: languageCode(for: localization.string("LANGUAGE") ?? ""),
                    path: path
                )
            }
            return nil
        }
    }

    private static func preferredLocalizedPath(_ resources: [LocalizedInstallerResource]) -> String? {
        resources.first { $0.languageCode == "en" }?.path ?? resources.first?.path
    }

    private static func applyBackgroundSettings(_ settings: [String: Any], to project: inout PackageProject, baseURL: URL) {
        let appearances = settings.dictionary("APPAREANCES")
        let lightSettings = appearances?.dictionary("LIGHT_AQUA")
        let darkSettings = appearances?.dictionary("DARK_AQUA")

        if let path = backgroundPath(in: lightSettings, baseURL: baseURL) ?? backgroundPath(in: settings, baseURL: baseURL) {
            project.backgroundPath = path
        }
        if let path = backgroundPath(in: darkSettings, baseURL: baseURL),
           path != project.backgroundPath {
            project.darkBackgroundPath = path
        }

        let preferredSettings = lightSettings ?? settings
        if let scaling = backgroundScaling(in: preferredSettings) {
            project.backgroundScaling = scaling
        }
        if let alignment = backgroundAlignment(in: preferredSettings) {
            project.backgroundAlignment = alignment
        }
    }

    private static func backgroundPath(in settings: [String: Any]?, baseURL: URL) -> String? {
        guard settings?.bool("CUSTOM", default: false) == true else {
            return nil
        }
        return resolvePath(settings?.dictionary("BACKGROUND_PATH"), baseURL: baseURL)
    }

    private static func backgroundScaling(in settings: [String: Any]?) -> InstallerBackgroundScaling? {
        switch settings?.int("SCALING") {
        case 0:
            return .proportional
        case 1:
            return .tofit
        case 2:
            return InstallerBackgroundScaling.none
        default:
            return nil
        }
    }

    private static func backgroundAlignment(in settings: [String: Any]?) -> InstallerBackgroundAlignment? {
        switch settings?.int("ALIGNMENT") {
        case 0:
            return .center
        case 1:
            return .top
        case 2:
            return .topleft
        case 3:
            return .topright
        case 4:
            return .left
        case 5:
            return .bottom
        case 6:
            return .bottomleft
        case 7:
            return .bottomright
        case 8:
            return .right
        default:
            return nil
        }
    }

    private static func languageCode(for packagesLanguage: String) -> String {
        let normalized = packagesLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map = [
            "arabic": "ar",
            "catalan": "ca",
            "chinese": "zh",
            "chinese (simplified)": "zh_CN",
            "chinese (traditional)": "zh_TW",
            "czech": "cs",
            "danish": "da",
            "dutch": "nl",
            "english": "en",
            "finnish": "fi",
            "french": "fr",
            "german": "de",
            "greek": "el",
            "hebrew": "he",
            "hungarian": "hu",
            "italian": "it",
            "japanese": "ja",
            "korean": "ko",
            "norwegian": "no",
            "polish": "pl",
            "portuguese": "pt",
            "portuguese (brazil)": "pt_BR",
            "russian": "ru",
            "spanish": "es",
            "swedish": "sv",
            "turkish": "tr",
            "ukrainian": "uk"
        ]
        if let code = map[normalized] {
            return code
        }
        if normalized.count <= 5, normalized.range(of: #"^[a-z]{2}([_-][a-z]{2})?$"#, options: .regularExpression) != nil {
            return normalized.replacingOccurrences(of: "-", with: "_")
        }
        return normalized.isEmpty ? "en" : normalized.replacingOccurrences(of: " ", with: "_")
    }

    private static func minimumSystemVersion(in requirements: [String: Any]?) -> String? {
        guard let list = requirements?["LIST"] as? [[String: Any]] else {
            return nil
        }
        for requirement in list {
            guard requirement.string("IDENTIFIER")?.contains("requirement.os") == true,
                  let dictionary = requirement.dictionary("DICTIONARY"),
                  let encodedVersion = dictionary.int("IC_REQUIREMENT_OS_MINIMUM_VERSION") else {
                continue
            }
            let major = encodedVersion / 10000
            let minor = (encodedVersion % 10000) / 100
            let patch = encodedVersion % 100
            return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
        }
        return nil
    }

    private static func choiceSettings(for packageUUID: String?, presentation: [String: Any]) -> (isSelected: Bool, isVisible: Bool) {
        guard let packageUUID,
              let installationType = presentation.dictionary("INSTALLATION TYPE"),
              let hierarchies = installationType.dictionary("HIERARCHIES"),
              let installer = hierarchies.dictionary("INSTALLER"),
              let list = installer["LIST"] as? [[String: Any]] else {
            return (true, true)
        }

        guard let item = list.first(where: { $0.string("PACKAGE_UUID") == packageUUID }),
              let options = item.dictionary("OPTIONS") else {
            return (true, true)
        }

        return (options.int("STATE", default: 1) != 0, !options.bool("HIDDEN", default: false))
    }

    private static func payloadItems(in packageFiles: [String: Any]?, baseURL: URL) -> [PackagePayloadEntry] {
        guard let hierarchy = packageFiles?.dictionary("HIERARCHY") else {
            return []
        }

        var items: [PackagePayloadEntry] = []
        collectPayloadItems(from: hierarchy, destinationParts: [], baseURL: baseURL, into: &items)
        return coalescedFolderContents(in: items)
    }

    private static func collectPayloadItems(
        from node: [String: Any],
        destinationParts: [String],
        baseURL: URL,
        into items: inout [PackagePayloadEntry]
    ) {
        let path = node.string("PATH") ?? ""
        let itemType = node.int("TYPE", default: 1)
        let children = node["CHILDREN"] as? [[String: Any]] ?? []

        if itemType == 3, let source = resolvePath(node, baseURL: baseURL) {
            let destination = normalizedDestination(destinationParts)
            items.append(PackagePayloadEntry(
                kind: .fileOrFolder,
                sourcePath: source,
                destinationPath: destination
            ))
            return
        }

        var nextDestinationParts = destinationParts
        if !path.isEmpty, path != "/" {
            nextDestinationParts.append(path)
        }

        let directoryDestination = normalizedDestination(nextDestinationParts)
        if children.isEmpty, directoryDestination != "/", !isStandardSystemDirectoryTemplate(directoryDestination) {
            items.append(PackagePayloadEntry(
                kind: .emptyDirectory,
                sourcePath: "",
                destinationPath: directoryDestination
            ))
        }

        for child in children {
            collectPayloadItems(from: child, destinationParts: nextDestinationParts, baseURL: baseURL, into: &items)
        }
    }

    private static func coalescedFolderContents(in entries: [PackagePayloadEntry]) -> [PackagePayloadEntry] {
        let emptyDirectories = entries.filter { $0.kind == .emptyDirectory }
        let fileEntries = entries.filter { $0.kind == .fileOrFolder }
        let grouped = Dictionary(grouping: fileEntries) { entry in
            "\(entry.destinationPath)|\(URL(fileURLWithPath: entry.sourcePath).deletingLastPathComponent().path)"
        }

        var result = emptyDirectories
        for group in grouped.values {
            guard group.count >= 3,
                  let first = group.first else {
                result.append(contentsOf: group)
                continue
            }
            let parent = URL(fileURLWithPath: first.sourcePath).deletingLastPathComponent().path
            result.append(PackagePayloadEntry(
                kind: .folderContents,
                sourcePath: parent,
                destinationPath: first.destinationPath
            ))
        }

        var seen: Set<String> = []
        return result.filter { entry in
            let key = "\(entry.kind.rawValue)|\(entry.sourcePath)|\(entry.destinationPath)"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private static func normalizedDestination(_ parts: [String]) -> String {
        let joined = parts
            .flatMap { $0.split(separator: "/") }
            .joined(separator: "/")
        return joined.isEmpty ? "/" : "/\(joined)"
    }

    private static func isStandardSystemDirectoryTemplate(_ path: String) -> Bool {
        standardSystemDirectoryTemplates.contains(normalizedAbsolutePath(path))
    }

    private static func normalizedAbsolutePath(_ path: String) -> String {
        let pieces = path.split(separator: "/").map(String.init)
        return pieces.isEmpty ? "/" : "/\(pieces.joined(separator: "/"))"
    }

    private static let standardSystemDirectoryTemplates: Set<String> = [
        "/Applications",
        "/Library",
        "/Library/Application Support",
        "/Library/Audio",
        "/Library/Automator",
        "/Library/ColorPickers",
        "/Library/ColorSync",
        "/Library/Components",
        "/Library/Contextual Menu Items",
        "/Library/Dictionaries",
        "/Library/Documentation",
        "/Library/Extensions",
        "/Library/Filesystems",
        "/Library/Fonts",
        "/Library/Frameworks",
        "/Library/Image Capture",
        "/Library/Input Methods",
        "/Library/Internet Plug-Ins",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/Modem Scripts",
        "/Library/PDF Services",
        "/Library/PreferencePanes",
        "/Library/Preference Panes",
        "/Library/Printers",
        "/Library/PrivilegedHelperTools",
        "/Library/QuickLook",
        "/Library/Receipts",
        "/Library/Screen Savers",
        "/Library/ScriptingAdditions",
        "/Library/Scripts",
        "/Library/Speech",
        "/Library/StartupItems",
        "/Library/WebServer"
    ]

    private static func resolvePath(_ dictionary: [String: Any]?, baseURL: URL) -> String? {
        guard let dictionary,
              let path = dictionary.string("PATH"),
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return expanded
        }
        return baseURL.appendingPathComponent(expanded).standardizedFileURL.path
    }

    private static func identifier(from base: String, suffix: String, index: Int) -> String {
        let cleanedSuffix = suffix
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeSuffix = cleanedSuffix.isEmpty ? "component\(index + 1)" : cleanedSuffix
        let cleanedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedBase.isEmpty ? "com.example.\(safeSuffix)" : "\(cleanedBase).\(safeSuffix)"
    }

    enum ImportError: LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            "The selected file is not a valid Packages project."
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    func int(_ key: String, default defaultValue: Int) -> Int {
        int(key) ?? defaultValue
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        if let value = self[key] as? Bool {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.boolValue
        }
        return defaultValue
    }
}
