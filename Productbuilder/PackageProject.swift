import Foundation

struct PackageProject: Codable, Equatable {
    var productName: String = "My Product"
    var productIdentifier: String = "com.example.myproduct"
    var productVersion: String = "1.0.0"
    var outputDirectory: String = "\(NSHomeDirectory())/Desktop"
    var resourcesDirectory: String = ""
    var logoPath: String = ""
    var backgroundPath: String = ""
    var darkBackgroundPath: String = ""
    var backgroundScaling: InstallerBackgroundScaling = .proportional
    var backgroundAlignment: InstallerBackgroundAlignment = .left
    var welcomePath: String = ""
    var readmePath: String = ""
    var licensePath: String = ""
    var conclusionPath: String = ""
    var welcomeLocalizations: [LocalizedInstallerResource] = []
    var readmeLocalizations: [LocalizedInstallerResource] = []
    var licenseLocalizations: [LocalizedInstallerResource] = []
    var conclusionLocalizations: [LocalizedInstallerResource] = []
    var signingIdentity: String = ""
    var allowCustomize: Bool = true
    var minimumSystemVersion: String = ""
    var enableAnywhereDomain: Bool = false
    var enableCurrentUserHomeDomain: Bool = false
    var enableLocalSystemDomain: Bool = true
    var generateUninstaller: Bool = true
    var components: [PackageComponent] = [PackageComponent()]

    var outputFileName: String {
        let cleanedName = productName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = cleanedName.isEmpty ? "Product" : cleanedName
        return "\(name)-\(productVersion).pkg"
    }

    var uninstallerFileName: String {
        let cleanedName = productName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = cleanedName.isEmpty ? "Product" : cleanedName
        return "Uninstall-\(name).sh"
    }
}

struct PackageComponent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Application"
    var sourcePath: String = ""
    var destinationPath: String = "/Applications"
    var payloadEntries: [PackagePayloadEntry] = []
    var packageIdentifier: String = "com.example.myproduct.app"
    var version: String = "1.0.0"
    var ownership: OwnershipMode = .recommended
    var isRequired: Bool = true
    var isSelected: Bool = true
    var isVisible: Bool = true
    var preinstallScriptPath: String = ""
    var postinstallScriptPath: String = ""

    var componentPackageName: String {
        let base = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return "\((base.isEmpty ? "Component" : base)).pkg"
    }
}

struct PackagePayloadEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: PackagePayloadKind = .fileOrFolder
    var sourcePath: String = ""
    var destinationPath: String = "/Applications"

    var title: String {
        switch kind {
        case .fileOrFolder:
            return sourcePath.isEmpty ? "File or Folder" : URL(fileURLWithPath: sourcePath).lastPathComponent
        case .folderContents:
            return sourcePath.isEmpty ? "Folder Contents" : "\(URL(fileURLWithPath: sourcePath).lastPathComponent) contents"
        case .emptyDirectory:
            return destinationPath.isEmpty ? "Empty Directory" : destinationPath
        }
    }
}

enum PackagePayloadKind: String, Codable, CaseIterable, Identifiable {
    case fileOrFolder
    case folderContents
    case emptyDirectory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fileOrFolder:
            return "File/Folder"
        case .folderContents:
            return "Folder Contents"
        case .emptyDirectory:
            return "Empty Directory"
        }
    }
}

struct LocalizedInstallerResource: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var languageCode: String = "en"
    var path: String = ""
}

extension PackageProject {
    enum CodingKeys: String, CodingKey {
        case productName
        case productIdentifier
        case productVersion
        case outputDirectory
        case resourcesDirectory
        case logoPath
        case backgroundPath
        case darkBackgroundPath
        case backgroundScaling
        case backgroundAlignment
        case welcomePath
        case readmePath
        case licensePath
        case conclusionPath
        case welcomeLocalizations
        case readmeLocalizations
        case licenseLocalizations
        case conclusionLocalizations
        case signingIdentity
        case allowCustomize
        case minimumSystemVersion
        case enableAnywhereDomain
        case enableCurrentUserHomeDomain
        case enableLocalSystemDomain
        case generateUninstaller
        case components
    }

    enum LegacyCodingKeys: String, CodingKey {
        case requireAdminInstall
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        productName = try container.decodeIfPresent(String.self, forKey: .productName) ?? productName
        productIdentifier = try container.decodeIfPresent(String.self, forKey: .productIdentifier) ?? productIdentifier
        productVersion = try container.decodeIfPresent(String.self, forKey: .productVersion) ?? productVersion
        outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? outputDirectory
        resourcesDirectory = try container.decodeIfPresent(String.self, forKey: .resourcesDirectory) ?? resourcesDirectory
        logoPath = try container.decodeIfPresent(String.self, forKey: .logoPath) ?? logoPath
        backgroundPath = try container.decodeIfPresent(String.self, forKey: .backgroundPath) ?? backgroundPath
        darkBackgroundPath = try container.decodeIfPresent(String.self, forKey: .darkBackgroundPath) ?? darkBackgroundPath
        backgroundScaling = try container.decodeIfPresent(InstallerBackgroundScaling.self, forKey: .backgroundScaling) ?? backgroundScaling
        backgroundAlignment = try container.decodeIfPresent(InstallerBackgroundAlignment.self, forKey: .backgroundAlignment) ?? backgroundAlignment
        welcomePath = try container.decodeIfPresent(String.self, forKey: .welcomePath) ?? welcomePath
        readmePath = try container.decodeIfPresent(String.self, forKey: .readmePath) ?? readmePath
        licensePath = try container.decodeIfPresent(String.self, forKey: .licensePath) ?? licensePath
        conclusionPath = try container.decodeIfPresent(String.self, forKey: .conclusionPath) ?? conclusionPath
        welcomeLocalizations = try container.decodeIfPresent([LocalizedInstallerResource].self, forKey: .welcomeLocalizations) ?? welcomeLocalizations
        readmeLocalizations = try container.decodeIfPresent([LocalizedInstallerResource].self, forKey: .readmeLocalizations) ?? readmeLocalizations
        licenseLocalizations = try container.decodeIfPresent([LocalizedInstallerResource].self, forKey: .licenseLocalizations) ?? licenseLocalizations
        conclusionLocalizations = try container.decodeIfPresent([LocalizedInstallerResource].self, forKey: .conclusionLocalizations) ?? conclusionLocalizations
        signingIdentity = try container.decodeIfPresent(String.self, forKey: .signingIdentity) ?? signingIdentity
        allowCustomize = try container.decodeIfPresent(Bool.self, forKey: .allowCustomize) ?? allowCustomize
        minimumSystemVersion = try container.decodeIfPresent(String.self, forKey: .minimumSystemVersion) ?? minimumSystemVersion
        generateUninstaller = try container.decodeIfPresent(Bool.self, forKey: .generateUninstaller) ?? generateUninstaller
        components = try container.decodeIfPresent([PackageComponent].self, forKey: .components) ?? components

        if let oldRequireAdminInstall = try legacyContainer.decodeIfPresent(Bool.self, forKey: .requireAdminInstall) {
            enableAnywhereDomain = !oldRequireAdminInstall
            enableCurrentUserHomeDomain = !oldRequireAdminInstall
            enableLocalSystemDomain = true
        } else {
            enableAnywhereDomain = try container.decodeIfPresent(Bool.self, forKey: .enableAnywhereDomain) ?? enableAnywhereDomain
            enableCurrentUserHomeDomain = try container.decodeIfPresent(Bool.self, forKey: .enableCurrentUserHomeDomain) ?? enableCurrentUserHomeDomain
            enableLocalSystemDomain = try container.decodeIfPresent(Bool.self, forKey: .enableLocalSystemDomain) ?? enableLocalSystemDomain
        }
    }
}

extension PackageComponent {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourcePath
        case destinationPath
        case payloadEntries
        case packageIdentifier
        case version
        case ownership
        case isRequired
        case isSelected
        case isVisible
        case preinstallScriptPath
        case postinstallScriptPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? name
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? sourcePath
        destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath) ?? destinationPath
        payloadEntries = try container.decodeIfPresent([PackagePayloadEntry].self, forKey: .payloadEntries) ?? payloadEntries
        if payloadEntries.isEmpty, !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payloadEntries = [PackagePayloadEntry(
                kind: .fileOrFolder,
                sourcePath: sourcePath,
                destinationPath: destinationPath
            )]
        }
        packageIdentifier = try container.decodeIfPresent(String.self, forKey: .packageIdentifier) ?? packageIdentifier
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? version
        ownership = try container.decodeIfPresent(OwnershipMode.self, forKey: .ownership) ?? ownership
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? isRequired
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? isSelected
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? isVisible
        preinstallScriptPath = try container.decodeIfPresent(String.self, forKey: .preinstallScriptPath) ?? preinstallScriptPath
        postinstallScriptPath = try container.decodeIfPresent(String.self, forKey: .postinstallScriptPath) ?? postinstallScriptPath
    }
}

enum InstallerBackgroundScaling: String, Codable, CaseIterable, Identifiable {
    case proportional
    case tofit
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proportional:
            return "Proportional"
        case .tofit:
            return "To Fit"
        case .none:
            return "None"
        }
    }
}

enum InstallerBackgroundAlignment: String, Codable, CaseIterable, Identifiable {
    case center
    case top
    case topleft
    case topright
    case left
    case bottom
    case bottomleft
    case bottomright
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center:
            return "Center"
        case .top:
            return "Top"
        case .topleft:
            return "Top Left"
        case .topright:
            return "Top Right"
        case .left:
            return "Left"
        case .bottom:
            return "Bottom"
        case .bottomleft:
            return "Bottom Left"
        case .bottomright:
            return "Bottom Right"
        case .right:
            return "Right"
        }
    }
}

enum OwnershipMode: String, Codable, CaseIterable, Identifiable {
    case recommended
    case preserve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            return "Recommended"
        case .preserve:
            return "Preserve"
        }
    }
}

@MainActor
final class PackageProjectModel: ObservableObject {
    @Published var project = PackageProject()
    @Published var projectURL: URL?
    @Published var selectedComponentID: PackageComponent.ID?
    @Published var log: String = ""
    @Published var isBuilding = false

    var selectedComponent: PackageComponent? {
        guard let selectedComponentID else { return project.components.first }
        return project.components.first { $0.id == selectedComponentID }
    }

    func reset() {
        project = PackageProject()
        projectURL = nil
        selectedComponentID = project.components.first?.id
        log = ""
    }

    func appendLog(_ message: String) {
        if log.isEmpty {
            log = message
        } else {
            log += "\n\(message)"
        }
    }

    func selectFirstComponentIfNeeded() {
        if selectedComponentID == nil || !project.components.contains(where: { $0.id == selectedComponentID }) {
            selectedComponentID = project.components.first?.id
        }
    }

    func updateSelectedComponent(_ update: (inout PackageComponent) -> Void) {
        guard let id = selectedComponent?.id,
              let index = project.components.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&project.components[index])
    }
}
