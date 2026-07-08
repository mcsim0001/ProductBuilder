import SwiftUI
import AppKit

@main
struct ProductbuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PackageProjectModel()
    @StateObject private var localization = AppLocalization()
    @StateObject private var recentProjects = RecentProjectsStore.shared
    @State private var showsHelp = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(localization)
                .frame(minWidth: ProductbuilderLayout.windowMinWidth, minHeight: ProductbuilderLayout.windowMinHeight)
                .sheet(isPresented: $showsHelp) {
                    ProductbuilderHelpView()
                        .environmentObject(localization)
                }
                .onAppear {
                    ApplicationIcon.install()
                    MenuLocalizer.apply(localization)
                }
                .onChange(of: localization.language) { _ in
                    MenuLocalizer.apply(localization)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(localization.t("menu.about")) {
                    AboutPanel.show(localization: localization)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(localization.t("menu.newProject")) {
                    model.reset()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button(localization.t("menu.open")) {
                    ProjectDocument.open(into: model)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Menu(localization.t("menu.recentProjects")) {
                    if recentProjects.entries.isEmpty {
                        Text(localization.t("menu.noRecentProjects"))
                    } else {
                        ForEach(recentProjects.entries) { entry in
                            Button(entry.displayName) {
                                openRecentProject(entry)
                            }
                        }

                        Divider()

                        Button(localization.t("menu.clearRecentProjects")) {
                            recentProjects.clear()
                        }
                    }
                }

                Button(localization.t("menu.importPackagesProject")) {
                    ProjectDocument.importPackagesProject(into: model)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button(localization.t("menu.close")) {
                    NSApplication.shared.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button(localization.t("menu.save")) {
                    ProjectDocument.save(model)
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button(localization.t("menu.saveAs")) {
                    ProjectDocument.saveAs(model)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button(localization.t("menu.installCommandLineTool")) {
                    CommandLineToolInstaller.install(localization: localization)
                }
            }

            CommandMenu(localization.t("language.menu")) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        localization.language = language
                    } label: {
                        if localization.language == language {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button(localization.t("menu.productbuilderHelp")) {
                    showsHelp = true
                }
                .keyboardShortcut("?", modifiers: [.command])
            }
        }
    }

    @MainActor
    private func openRecentProject(_ entry: RecentProjectEntry) {
        guard FileManager.default.fileExists(atPath: entry.path) else {
            recentProjects.remove(entry)
            model.appendLog(localization.t("recent.missing", entry.path))
            return
        }
        ProjectDocument.open(entry.url, into: model)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableSuddenTermination()
        ApplicationIcon.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

enum ApplicationIcon {
    static func image() -> NSImage? {
        if let assetIcon = NSImage(named: "AppIcon") {
            return assetIcon
        }
        if let applicationIcon = NSImage(named: NSImage.applicationIconName) {
            return applicationIcon
        }
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            return icon
        }
        return nil
    }

    @MainActor
    static func install() {
        guard let icon = image() else { return }
        NSApplication.shared.applicationIconImage = icon
    }
}

private enum AboutPanel {
    @MainActor
    static func show(localization: AppLocalization) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let icon = ApplicationIcon.image() {
            options[.applicationIcon] = icon
        }
        options[.applicationName] = "Productbuilder"
        options[.applicationVersion] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        options[.version] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        options[.credits] = NSAttributedString(
            string: localization.t("about.credits"),
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
}

private enum CommandLineToolInstaller {
    private static let linkPath = "/usr/local/bin/productbuilder"

    @MainActor
    static func install(localization: AppLocalization) {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("productbuilder")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            showAlert(
                title: localization.t("cli.install.failure.title"),
                message: localization.t("cli.install.missingHelper", helperURL.path),
                style: .critical
            )
            return
        }

        let script = installScript(helperPath: helperURL.path, linkPath: linkPath)
        let source = "do shell script \(appleScriptStringLiteral(script)) with administrator privileges"

        guard let appleScript = NSAppleScript(source: source) else {
            showAlert(
                title: localization.t("cli.install.failure.title"),
                message: localization.t("cli.install.unableToCreateScript"),
                style: .critical
            )
            return
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let errorNumber = errorInfo["NSAppleScriptErrorNumber"] as? Int
            if errorNumber == -128 {
                return
            }

            let message = errorInfo["NSAppleScriptErrorMessage"] as? String
                ?? localization.t("cli.install.unknownError")
            showAlert(
                title: localization.t("cli.install.failure.title"),
                message: message,
                style: .critical
            )
            return
        }

        showAlert(
            title: localization.t("cli.install.success.title"),
            message: localization.t("cli.install.success.message", linkPath, helperURL.path),
            style: .informational
        )
    }

    private static func installScript(helperPath: String, linkPath: String) -> String {
        let helper = shellQuoted(helperPath)
        let link = shellQuoted(linkPath)
        return """
        set -e; helper=\(helper); link=\(link); if [ ! -x "$helper" ]; then echo "Command line tool is missing from the app bundle: $helper" >&2; exit 64; fi; mkdir -p "$(dirname "$link")"; if [ -e "$link" ] && [ ! -L "$link" ]; then echo "$link already exists and is not a symlink. Remove it manually or choose another command name." >&2; exit 65; fi; ln -sfn "$helper" "$link"
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    @MainActor
    private static func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.icon = ApplicationIcon.image()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct ProductbuilderHelpView: View {
    @EnvironmentObject private var localization: AppLocalization
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon = ApplicationIcon.image() {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.t("help.window.title"))
                        .font(.title2.weight(.semibold))
                    Text(localization.t("help.window.subtitle"))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(localization.t("button.close")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helpSection(
                        title: localization.t("help.overview.title"),
                        lines: [
                            localization.t("help.overview.body"),
                            localization.t("help.overview.workflow")
                        ]
                    )

                    helpSection(
                        title: localization.t("components.title"),
                        lines: [localization.t("components.help.body")]
                    )

                    helpSection(
                        title: localization.t("section.selectedComponent"),
                        lines: [
                            localization.t("help.component.name"),
                            localization.t("help.component.identifier"),
                            localization.t("help.component.version"),
                            localization.t("help.component.choice"),
                            localization.t("help.component.scripts")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.payload"),
                        lines: [
                            localization.t("help.payload.fileFolder"),
                            localization.t("help.payload.folderContents"),
                            localization.t("help.payload.emptyDirectory"),
                            localization.t("help.payload.destination"),
                            localization.t("help.payload.permissions"),
                            localization.t("help.payload.permissions.principals"),
                            localization.t("help.payload.permissions.modes"),
                            localization.t("help.payload.permissions.bundle")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.product"),
                        lines: [
                            localization.t("help.product.name"),
                            localization.t("help.product.identifier"),
                            localization.t("help.product.version"),
                            localization.t("help.product.output"),
                            localization.t("help.product.openOutputAfterBuild"),
                            localization.t("help.product.resources"),
                            localization.t("help.product.signing"),
                            localization.t("help.product.notarization")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.installerScreens"),
                        lines: [
                            localization.t("help.design.logo"),
                            localization.t("help.design.background"),
                            localization.t("help.design.scaling"),
                            localization.t("help.design.pages"),
                            localization.t("help.design.localizations")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.installationRules"),
                        lines: [
                            localization.t("help.rules.minimum"),
                            localization.t("help.rules.customize"),
                            localization.t("help.rules.localSystem"),
                            localization.t("help.rules.currentUserHome"),
                            localization.t("help.rules.anywhere")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.preview"),
                        lines: [
                            localization.t("help.preview.page"),
                            localization.t("help.preview.localization"),
                            localization.t("help.preview.appearance"),
                            localization.t("help.preview.approximate")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.uninstaller"),
                        lines: [
                            localization.t("help.uninstaller.generate"),
                            localization.t("help.uninstaller.removes"),
                            localization.t("help.uninstaller.emptyDirs")
                        ]
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 660, minHeight: 620)
    }

    private func helpSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
private enum MenuLocalizer {
    @MainActor
    static func apply(_ localization: AppLocalization) {
        Task { @MainActor in
            guard let mainMenu = NSApplication.shared.mainMenu else { return }

            for item in mainMenu.items {
                localizeTopLevelItem(item, localization: localization)
                if let submenu = item.submenu {
                    localizeItems(in: submenu, localization: localization)
                }
            }
        }
    }

    @MainActor
    private static func localizeTopLevelItem(_ item: NSMenuItem, localization: AppLocalization) {
        guard let key = localizationKey(for: item, candidates: topLevelMenuKeys, localization: localization) else { return }
        rememberLocalizationKey(key, for: item)
        item.title = localization.t(key)
        item.submenu?.title = localization.t(key)
    }

    @MainActor
    private static func localizeItems(in menu: NSMenu, localization: AppLocalization) {
        for item in menu.items {
            if let key = menuItemKey(for: item, localization: localization) {
                rememberLocalizationKey(key, for: item)
                item.title = localization.t(key)
            }

            if let submenu = item.submenu {
                localizeItems(in: submenu, localization: localization)
            }
        }
    }

    private static func menuItemKey(for item: NSMenuItem, localization: AppLocalization) -> String? {
        localizationKey(for: item, candidates: menuItemKeys, localization: localization)
            ?? actionMenuItemKey(for: item)
    }

    private static func localizationKey(
        for item: NSMenuItem,
        candidates: [String],
        localization: AppLocalization
    ) -> String? {
        if let identifier = item.identifier?.rawValue,
           identifier.hasPrefix(localizationIdentifierPrefix) {
            return String(identifier.dropFirst(localizationIdentifierPrefix.count))
        }

        return candidates.first { key in
            AppLanguage.allCases.contains { language in
                localization.localizedString(for: key, language: language).map {
                    normalizedMenuTitle($0) == normalizedMenuTitle(item.title)
                } ?? false
            }
        }
    }

    private static func rememberLocalizationKey(_ key: String, for item: NSMenuItem) {
        item.identifier = NSUserInterfaceItemIdentifier(localizationIdentifierPrefix + key)
    }

    private static func normalizedMenuTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "…", with: "...")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func actionMenuItemKey(for item: NSMenuItem) -> String? {
        guard let action = item.action else { return nil }
        return actionMenuItemKeys[NSStringFromSelector(action)]
    }

    private static let localizationIdentifierPrefix = "productbuilder.localization."

    private static let topLevelMenuKeys = [
        "menu.file",
        "menu.edit",
        "menu.view",
        "language.menu",
        "menu.window",
        "menu.help"
    ]

    private static let menuItemKeys = [
        "menu.about",
        "menu.hideApp",
        "menu.hideOthers",
        "menu.showAll",
        "menu.quitApp",
        "menu.close",
        "menu.closeWindow",
        "menu.save",
        "menu.saveAs",
        "menu.installCommandLineTool",
        "menu.services",
        "menu.noServicesApply",
        "menu.undo",
        "menu.redo",
        "menu.cut",
        "menu.copy",
        "menu.paste",
        "menu.pasteAndMatchStyle",
        "menu.delete",
        "menu.selectAll",
        "menu.find",
        "menu.findEllipsis",
        "menu.findAndReplace",
        "menu.findNext",
        "menu.findPrevious",
        "menu.useSelectionForFind",
        "menu.jumpToSelection",
        "menu.spellingAndGrammar",
        "menu.showSpellingAndGrammar",
        "menu.checkDocumentNow",
        "menu.checkSpellingWhileTyping",
        "menu.checkGrammarWithSpelling",
        "menu.correctSpellingAutomatically",
        "menu.substitutions",
        "menu.showSubstitutions",
        "menu.smartCopyPaste",
        "menu.smartQuotes",
        "menu.smartDashes",
        "menu.smartLinks",
        "menu.dataDetectors",
        "menu.textReplacement",
        "menu.transformations",
        "menu.makeUpperCase",
        "menu.makeLowerCase",
        "menu.capitalize",
        "menu.speech",
        "menu.startSpeaking",
        "menu.stopSpeaking",
        "menu.startDictation",
        "menu.emojiAndSymbols",
        "menu.customizeTouchBar",
        "menu.showToolbar",
        "menu.hideToolbar",
        "menu.customizeToolbar",
        "menu.showTabBar",
        "menu.showAllTabs",
        "menu.enterFullScreen",
        "menu.exitFullScreen",
        "menu.minimize",
        "menu.zoom",
        "menu.bringAllToFront",
        "menu.productbuilderHelp"
    ]

    private static let actionMenuItemKeys = [
        "hide:": "menu.hideApp",
        "hideOtherApplications:": "menu.hideOthers",
        "unhideAllApplications:": "menu.showAll",
        "terminate:": "menu.quitApp",
        "undo:": "menu.undo",
        "redo:": "menu.redo",
        "cut:": "menu.cut",
        "copy:": "menu.copy",
        "paste:": "menu.paste",
        "delete:": "menu.delete",
        "selectAll:": "menu.selectAll",
        "startSpeaking:": "menu.startSpeaking",
        "stopSpeaking:": "menu.stopSpeaking",
        "toggleToolbarShown:": "menu.showToolbar",
        "runToolbarCustomizationPalette:": "menu.customizeToolbar",
        "toggleTabBar:": "menu.showTabBar",
        "toggleFullScreen:": "menu.enterFullScreen",
        "performMiniaturize:": "menu.minimize",
        "performZoom:": "menu.zoom",
        "arrangeInFront:": "menu.bringAllToFront"
    ]
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case ukrainian = "uk"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"
    case arabic = "ar"
    case bengali = "bn"
    case portugueseBrazil = "pt-BR"
    case indonesian = "id"
    case french = "fr"
    case german = "de"
    case japanese = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .ukrainian:
            return "Українська"
        case .spanish:
            return "Español"
        case .chineseSimplified:
            return "简体中文"
        case .hindi:
            return "हिन्दी"
        case .arabic:
            return "العربية"
        case .bengali:
            return "বাংলা"
        case .portugueseBrazil:
            return "Português (Brasil)"
        case .indonesian:
            return "Bahasa Indonesia"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
        case .japanese:
            return "日本語"
        }
    }
}

@MainActor
final class AppLocalization: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        }
    }

    private let storageKey = "Productbuilder.AppLanguage"

    init() {
        let savedCode = UserDefaults.standard.string(forKey: storageKey)
        language = AppLanguage(rawValue: savedCode ?? "") ?? .english
    }

    func t(_ key: String) -> String {
        t(key, fallback: key)
    }

    func t(_ key: String, fallback: String) -> String {
        if let value = localizedValue(for: key, language: language) {
            return value
        }
        if language != .english, let value = localizedValue(for: key, language: .english) {
            return value
        }
        return fallback
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    func localizedString(for key: String, language: AppLanguage) -> String? {
        localizedValue(for: key, language: language)
            ?? (language == .english ? nil : localizedValue(for: key, language: .english))
    }

    private func localizedValue(for key: String, language: AppLanguage) -> String? {
        guard let bundle = Self.localizedBundle(for: language) else {
            return nil
        }

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
