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
                .frame(minWidth: 1120, minHeight: 720)
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

private enum ApplicationIcon {
    static func image() -> NSImage? {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: iconURL)
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
                            localization.t("help.component.ownership"),
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
                            localization.t("help.payload.destination")
                        ]
                    )

                    helpSection(
                        title: localization.t("section.product"),
                        lines: [
                            localization.t("help.product.name"),
                            localization.t("help.product.identifier"),
                            localization.t("help.product.version"),
                            localization.t("help.product.output"),
                            localization.t("help.product.resources"),
                            localization.t("help.product.signing")
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
        guard let key = topLevelMenuKey(for: item.title) else { return }
        item.title = localization.t(key)
        item.submenu?.title = localization.t(key)
    }

    @MainActor
    private static func localizeItems(in menu: NSMenu, localization: AppLocalization) {
        for item in menu.items {
            if let key = menuItemKey(for: item.title) {
                item.title = localization.t(key)
            }

            if let submenu = item.submenu {
                localizeItems(in: submenu, localization: localization)
            }
        }
    }

    private static func topLevelMenuKey(for title: String) -> String? {
        switch title {
        case "File", "Файл":
            return "menu.file"
        case "Edit", "Редагування":
            return "menu.edit"
        case "View", "Вигляд":
            return "menu.view"
        case "Language", "Мова":
            return "language.menu"
        case "Window", "Вікно":
            return "menu.window"
        case "Help", "Довідка":
            return "menu.help"
        default:
            return nil
        }
    }

    private static func menuItemKey(for title: String) -> String? {
        switch title {
        case "About Productbuilder", "Про Productbuilder":
            return "menu.about"
        case "Hide Productbuilder", "Сховати Productbuilder":
            return "menu.hideApp"
        case "Hide Others", "Сховати інші":
            return "menu.hideOthers"
        case "Show All", "Показати всі":
            return "menu.showAll"
        case "Quit Productbuilder", "Завершити Productbuilder":
            return "menu.quitApp"
        case "Close", "Закрити":
            return "menu.close"
        case "Close Window", "Закрити вікно":
            return "menu.closeWindow"
        case "Save", "Зберегти":
            return "menu.save"
        case "Save As...", "Save As…", "Зберегти як...", "Зберегти як…":
            return "menu.saveAs"
        case "Services", "Служби":
            return "menu.services"
        case "No Services Apply", "Немає доступних служб":
            return "menu.noServicesApply"
        case "Undo", "Скасувати":
            return "menu.undo"
        case "Redo", "Повторити":
            return "menu.redo"
        case "Cut", "Вирізати":
            return "menu.cut"
        case "Copy", "Копіювати":
            return "menu.copy"
        case "Paste", "Вставити":
            return "menu.paste"
        case "Paste and Match Style", "Вставити й узгодити стиль":
            return "menu.pasteAndMatchStyle"
        case "Delete", "Видалити":
            return "menu.delete"
        case "Select All", "Вибрати все":
            return "menu.selectAll"
        case "Find", "Знайти":
            return "menu.find"
        case "Find...", "Знайти...":
            return "menu.findEllipsis"
        case "Find and Replace...", "Знайти й замінити...":
            return "menu.findAndReplace"
        case "Find Next", "Знайти далі":
            return "menu.findNext"
        case "Find Previous", "Знайти попереднє":
            return "menu.findPrevious"
        case "Use Selection for Find", "Використати вибране для пошуку":
            return "menu.useSelectionForFind"
        case "Jump to Selection", "Перейти до вибраного":
            return "menu.jumpToSelection"
        case "Spelling and Grammar", "Правопис і граматика":
            return "menu.spellingAndGrammar"
        case "Show Spelling and Grammar", "Показати правопис і граматику":
            return "menu.showSpellingAndGrammar"
        case "Check Document Now", "Перевірити документ зараз":
            return "menu.checkDocumentNow"
        case "Check Spelling While Typing", "Перевіряти правопис під час введення":
            return "menu.checkSpellingWhileTyping"
        case "Check Grammar With Spelling", "Перевіряти граматику разом із правописом":
            return "menu.checkGrammarWithSpelling"
        case "Correct Spelling Automatically", "Автоматично виправляти правопис":
            return "menu.correctSpellingAutomatically"
        case "Substitutions", "Заміни":
            return "menu.substitutions"
        case "Show Substitutions", "Показати заміни":
            return "menu.showSubstitutions"
        case "Smart Copy/Paste", "Розумне копіювання/вставлення":
            return "menu.smartCopyPaste"
        case "Smart Quotes", "Розумні лапки":
            return "menu.smartQuotes"
        case "Smart Dashes", "Розумні тире":
            return "menu.smartDashes"
        case "Smart Links", "Розумні посилання":
            return "menu.smartLinks"
        case "Data Detectors", "Детектори даних":
            return "menu.dataDetectors"
        case "Text Replacement", "Заміна тексту":
            return "menu.textReplacement"
        case "Transformations", "Перетворення":
            return "menu.transformations"
        case "Make Upper Case", "Зробити великими літерами":
            return "menu.makeUpperCase"
        case "Make Lower Case", "Зробити малими літерами":
            return "menu.makeLowerCase"
        case "Capitalize", "Капіталізувати":
            return "menu.capitalize"
        case "Speech", "Мовлення":
            return "menu.speech"
        case "Start Speaking", "Почати промовляння":
            return "menu.startSpeaking"
        case "Stop Speaking", "Зупинити промовляння":
            return "menu.stopSpeaking"
        case "Start Dictation...", "Почати диктування...":
            return "menu.startDictation"
        case "Emoji & Symbols", "Емодзі та символи":
            return "menu.emojiAndSymbols"
        case "Customize Touch Bar...", "Налаштувати Touch Bar...":
            return "menu.customizeTouchBar"
        case "Show Toolbar", "Показати панель інструментів":
            return "menu.showToolbar"
        case "Hide Toolbar", "Сховати панель інструментів":
            return "menu.hideToolbar"
        case "Customize Toolbar...", "Налаштувати панель інструментів...":
            return "menu.customizeToolbar"
        case "Show Tab Bar", "Показати панель вкладок":
            return "menu.showTabBar"
        case "Show All Tabs", "Показати всі вкладки":
            return "menu.showAllTabs"
        case "Enter Full Screen", "Увійти в повноекранний режим":
            return "menu.enterFullScreen"
        case "Exit Full Screen", "Вийти з повноекранного режиму":
            return "menu.exitFullScreen"
        case "Minimize", "Згорнути":
            return "menu.minimize"
        case "Zoom", "Масштабувати":
            return "menu.zoom"
        case "Bring All to Front", "Всі вікна на передній план":
            return "menu.bringAllToFront"
        case "Productbuilder Help", "Довідка Productbuilder":
            return "menu.productbuilderHelp"
        default:
            return nil
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case ukrainian = "uk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .ukrainian:
            return "Українська"
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
        Self.translations[language]?[key] ?? Self.translations[.english]?[key] ?? key
    }

    func t(_ key: String, fallback: String) -> String {
        Self.translations[language]?[key] ?? Self.translations[.english]?[key] ?? fallback
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    static let translations: [AppLanguage: [String: String]] = [
        .english: [
            "menu.newProject": "New Project",
            "menu.open": "Open...",
            "menu.importPackagesProject": "Import Packages Project...",
            "menu.save": "Save",
            "menu.saveAs": "Save As...",
            "menu.about": "About Productbuilder",
            "menu.recentProjects": "Recent",
            "menu.noRecentProjects": "No Recent Projects",
            "menu.clearRecentProjects": "Clear Menu",
            "menu.file": "File",
            "menu.edit": "Edit",
            "menu.view": "View",
            "menu.window": "Window",
            "menu.help": "Help",
            "menu.productbuilderHelp": "Productbuilder Help",
            "menu.hideApp": "Hide Productbuilder",
            "menu.hideOthers": "Hide Others",
            "menu.showAll": "Show All",
            "menu.quitApp": "Quit Productbuilder",
            "menu.close": "Close",
            "menu.closeWindow": "Close Window",
            "menu.services": "Services",
            "menu.noServicesApply": "No Services Apply",
            "menu.undo": "Undo",
            "menu.redo": "Redo",
            "menu.cut": "Cut",
            "menu.copy": "Copy",
            "menu.paste": "Paste",
            "menu.pasteAndMatchStyle": "Paste and Match Style",
            "menu.delete": "Delete",
            "menu.selectAll": "Select All",
            "menu.find": "Find",
            "menu.findEllipsis": "Find...",
            "menu.findAndReplace": "Find and Replace...",
            "menu.findNext": "Find Next",
            "menu.findPrevious": "Find Previous",
            "menu.useSelectionForFind": "Use Selection for Find",
            "menu.jumpToSelection": "Jump to Selection",
            "menu.spellingAndGrammar": "Spelling and Grammar",
            "menu.showSpellingAndGrammar": "Show Spelling and Grammar",
            "menu.checkDocumentNow": "Check Document Now",
            "menu.checkSpellingWhileTyping": "Check Spelling While Typing",
            "menu.checkGrammarWithSpelling": "Check Grammar With Spelling",
            "menu.correctSpellingAutomatically": "Correct Spelling Automatically",
            "menu.substitutions": "Substitutions",
            "menu.showSubstitutions": "Show Substitutions",
            "menu.smartCopyPaste": "Smart Copy/Paste",
            "menu.smartQuotes": "Smart Quotes",
            "menu.smartDashes": "Smart Dashes",
            "menu.smartLinks": "Smart Links",
            "menu.dataDetectors": "Data Detectors",
            "menu.textReplacement": "Text Replacement",
            "menu.transformations": "Transformations",
            "menu.makeUpperCase": "Make Upper Case",
            "menu.makeLowerCase": "Make Lower Case",
            "menu.capitalize": "Capitalize",
            "menu.speech": "Speech",
            "menu.startSpeaking": "Start Speaking",
            "menu.stopSpeaking": "Stop Speaking",
            "menu.startDictation": "Start Dictation...",
            "menu.emojiAndSymbols": "Emoji & Symbols",
            "menu.customizeTouchBar": "Customize Touch Bar...",
            "menu.showToolbar": "Show Toolbar",
            "menu.hideToolbar": "Hide Toolbar",
            "menu.customizeToolbar": "Customize Toolbar...",
            "menu.showTabBar": "Show Tab Bar",
            "menu.showAllTabs": "Show All Tabs",
            "menu.enterFullScreen": "Enter Full Screen",
            "menu.exitFullScreen": "Exit Full Screen",
            "menu.minimize": "Minimize",
            "menu.zoom": "Zoom",
            "menu.bringAllToFront": "Bring All to Front",
            "language.menu": "Language",
            "language.contextTitle": "Application Language",
            "toolbar.open": "Open",
            "toolbar.open.help": "Open a Productbuilder project",
            "toolbar.import": "Import",
            "toolbar.import.help": "Import a Packages .pkgproj project",
            "toolbar.save": "Save",
            "toolbar.save.help": "Save the current project",
            "toolbar.build": "Build",
            "toolbar.build.help": "Build the installer package",
            "toolbar.build.running": "Build is running",
            "components.title": "Components",
            "components.help.label": "Components Help",
            "components.help.tooltip": "What are components?",
            "components.help.body": "This list contains installer package components. Add one component for each app, helper, resource pack, or optional payload group you want to build into the product package.",
            "components.untitled": "Untitled Component",
            "components.add.help": "Add component",
            "components.remove.help": "Remove selected component",
            "button.add": "Add",
            "button.remove": "Remove",
            "button.clear": "Clear",
            "button.continue": "Continue",
            "button.close": "Close",
            "component.selectPrompt": "Select a component.",
            "component.newName": "Component %d",
            "tab.component": "Component",
            "tab.product": "Product",
            "tab.design": "Design",
            "tab.preview": "Preview",
            "section.product": "Product",
            "section.installerScreens": "Installer Screens",
            "section.installationRules": "Installation Rules",
            "section.uninstaller": "Uninstaller",
            "section.selectedComponent": "Selected Component",
            "section.preview": "Preview",
            "section.payload": "Payload",
            "field.name": "Name",
            "field.identifier": "Identifier",
            "field.version": "Version",
            "field.output": "Output",
            "field.resources": "Resources",
            "field.signing": "Signing",
            "field.logo": "Package Icon",
            "field.background": "Background",
            "field.darkBackground": "Dark Background",
            "field.scaling": "Scaling",
            "field.alignment": "Alignment",
            "field.minimumMacOS": "Minimum macOS",
            "field.customize": "Customize",
            "field.domains": "Domains",
            "field.ownership": "Ownership",
            "field.choice": "Choice",
            "field.preinstall": "Preinstall",
            "field.postinstall": "Postinstall",
            "field.destination": "Destination",
            "placeholder.productName": "Product name",
            "placeholder.componentName": "Application",
            "picker.ownership": "Ownership",
            "picker.minimumMacOS": "Minimum macOS",
            "picker.page": "Page",
            "picker.localization": "Localization",
            "picker.appearance": "Appearance",
            "picker.language": "Language",
            "picker.payloadKind": "Payload kind",
            "toggle.allowCustomize": "Allow component selection in Installer",
            "toggle.localSystem": "Local system",
            "toggle.currentUserHome": "Current user home",
            "toggle.anywhere": "Anywhere",
            "toggle.generateUninstaller": "Generate uninstall shell script beside the .pkg",
            "toggle.required": "Required",
            "toggle.selectedByDefault": "Selected by default",
            "toggle.visibleInCustomize": "Visible in customize list",
            "page.welcome": "Welcome",
            "page.readme": "Read Me",
            "page.license": "License",
            "page.conclusion": "Conclusion",
            "appearance.light": "Light",
            "appearance.dark": "Dark",
            "preview.page": "Page",
            "preview.localization": "Localization",
            "preview.defaultLocalization": "Default",
            "preview.appearance": "Appearance",
            "preview.installerFallback": "Installer",
            "preview.productFallback": "Product",
            "preview.noResource": "No resource selected for this page.",
            "preview.unable": "Unable to preview %@.",
            "preview.installerTitle": "Install: %@",
            "preview.welcomeHeading": "Welcome to the %@ Installer",
            "preview.defaultWelcomeBody": "You will be guided through the steps necessary to install this software.",
            "preview.step.introduction": "Introduction",
            "preview.step.destination": "Destination Select",
            "preview.step.installationType": "Installation Type",
            "preview.step.installation": "Installation",
            "preview.step.summary": "Summary",
            "signing.unsigned": "Unsigned",
            "signing.choose": "Choose Identity",
            "signing.choose.help": "Choose signing identity",
            "signing.refresh": "Refresh Identities",
            "signing.refresh.help": "Refresh identities",
            "buildLog.title": "Build Log",
            "buildLog.clear.help": "Clear build log",
            "buildLog.empty": "No build output yet.",
            "buildLog.done": "Done: %@",
            "buildLog.uninstaller": "Uninstaller: %@",
            "buildLog.failed": "Build failed: %@",
            "recent.missing": "Recent project not found: %@",
            "scaling.proportional": "Proportional",
            "scaling.toFit": "To Fit",
            "scaling.none": "None",
            "alignment.center": "Center",
            "alignment.top": "Top",
            "alignment.topLeft": "Top Left",
            "alignment.topRight": "Top Right",
            "alignment.left": "Left",
            "alignment.bottom": "Bottom",
            "alignment.bottomLeft": "Bottom Left",
            "alignment.bottomRight": "Bottom Right",
            "alignment.right": "Right",
            "ownership.recommended": "Recommended",
            "ownership.preserve": "Preserve",
            "payload.fileFolder": "File/Folder",
            "payload.fileOrFolder": "File or Folder",
            "payload.folderContents": "Folder Contents",
            "payload.emptyDirectory": "Empty Directory",
            "payload.add": "Add Payload",
            "payload.add.help": "Add payload entry",
            "payload.remove.help": "Remove payload entry",
            "payload.empty": "No payload entries. Add a file, folder contents, or an empty directory.",
            "localization.title": "Localizations",
            "localization.add": "Add Localization",
            "localization.add.help": "Add localization",
            "localization.remove.help": "Remove localization",
            "localization.language.help": "Choose the language for this localized installer page",
            "macos.noMinimum": "No minimum",
            "macos.custom": "Custom: %@",
            "macos.help": "Choose the oldest macOS version allowed to install this product.",
            "path.optional": "Optional",
            "path.choosePath": "Choose path",
            "path.choose": "Choose",
            "path.choose.help": "Choose path",
            "path.chooseOptional.help": "Choose optional path",
            "about.credits": "A focused macOS tool for creating product .pkg installers from components, payload entries, installer resources, localized pages, signing settings, and optional uninstall scripts.",
            "help.window.title": "Productbuilder Help",
            "help.window.subtitle": "A practical guide to the app and its installer-building options.",
            "help.overview.title": "What Productbuilder Does",
            "help.overview.body": "Productbuilder creates macOS product .pkg installers. It can build component packages, combine them into a product package, import Packages .pkgproj projects, configure payload files and folders, generate installer resources, preview installer pages, sign output packages, and create a companion uninstall script.",
            "help.overview.workflow": "A typical workflow is: add components, define each component's payload, configure product metadata, add installer pages and localizations, preview the result, choose signing, then build the final .pkg.",
            "help.about": "About %@",
            "help.product.name": "Name: display name of the final installer product.",
            "help.product.identifier": "Identifier: reverse-DNS product id used by macOS Installer receipts.",
            "help.product.version": "Version: product version written into the generated package.",
            "help.product.output": "Output: folder where the final .pkg and optional uninstaller are created.",
            "help.product.resources": "Resources: optional installer resources folder for files referenced by distribution.xml.",
            "help.product.signing": "Signing: Developer ID Installer identity used to sign the final product package.",
            "help.design.logo": "Package Icon: optional image applied to the final .pkg file and shown in Installer's title bar.",
            "help.design.background": "Background and Dark Background: images used behind the Installer window. If Dark Background is empty, Background is used for both light and dark appearances.",
            "help.design.scaling": "Scaling and Alignment: how the background image is placed in the Installer window.",
            "help.design.pages": "Welcome, Read Me, License, Conclusion: Installer pages copied into the resources folder and referenced from distribution.xml.",
            "help.design.localizations": "Localizations: language-specific variants of each page, written into .lproj folders.",
            "help.rules.minimum": "Minimum macOS: optional version requirement for the installer.",
            "help.rules.customize": "Customize: allows the user to choose visible optional components in Installer.",
            "help.rules.localSystem": "Local system: enables installing for the whole Mac, usually the normal mode for /Applications and /Library payloads.",
            "help.rules.currentUserHome": "Current user home: enables per-user installation into the selected user's home domain.",
            "help.rules.anywhere": "Anywhere: allows selecting another destination volume or path when Installer supports it.",
            "help.uninstaller.generate": "Generate uninstall shell script: creates a companion script beside the final .pkg.",
            "help.uninstaller.removes": "The script removes installed payload files that Productbuilder can safely track during the build.",
            "help.uninstaller.emptyDirs": "Empty directory entries are created by the installer but are not aggressively removed by the generated script.",
            "help.ownership.short": "Recommended lets pkgbuild apply standard installer ownership. Preserve keeps ownership from the source files.",
            "help.choice.required": "User cannot deselect this component in Installer. Required components are always selected.",
            "help.choice.selected": "Component is selected when Installer opens the Customize list.",
            "help.choice.visible": "Show this component in Installer's Customize list.",
            "help.component.name": "Name: label for this component in Productbuilder and Installer choices.",
            "help.component.identifier": "Identifier: reverse-DNS id for this component package receipt.",
            "help.component.version": "Version: component package version passed to pkgbuild.",
            "help.component.ownership": "Ownership: Recommended lets pkgbuild apply standard ownership; Preserve keeps ownership from source files.",
            "help.component.choice": "Choice: controls whether the component is required, selected by default, and visible in Installer Customize.",
            "help.component.scripts": "Preinstall and Postinstall: optional shell scripts executed by this component package.",
            "help.preview.page": "Page: selects which Installer page to preview.",
            "help.preview.localization": "Localization: shows the default resource or a localized .lproj variant.",
            "help.preview.appearance": "Appearance: switches between light and dark background choices.",
            "help.preview.approximate": "Preview is approximate; the final layout is still rendered by macOS Installer.",
            "help.payload.fileFolder": "File/Folder: copies the selected file or folder itself into the destination.",
            "help.payload.folderContents": "Folder Contents: copies the current contents of a source folder into a fixed destination folder at build time.",
            "help.payload.emptyDirectory": "Empty Directory: creates a destination folder without requiring a source path.",
            "help.payload.destination": "Destination: absolute install path where this payload entry will be staged.",
            "installerLanguage.en": "English",
            "installerLanguage.uk": "Ukrainian",
            "installerLanguage.es": "Spanish",
            "installerLanguage.fr": "French",
            "installerLanguage.de": "German",
            "installerLanguage.it": "Italian",
            "installerLanguage.pt_BR": "Portuguese",
            "installerLanguage.pl": "Polish",
            "installerLanguage.ru": "Russian",
            "installerLanguage.zh_CN": "Chinese Simplified",
            "installerLanguage.zh_TW": "Chinese Traditional",
            "installerLanguage.ja": "Japanese",
            "installerLanguage.ko": "Korean",
            "installerLanguage.nl": "Dutch",
            "installerLanguage.tr": "Turkish",
            "installerLanguage.custom": "Custom"
        ],
        .ukrainian: [
            "menu.newProject": "Новий проєкт",
            "menu.open": "Відкрити...",
            "menu.importPackagesProject": "Імпортувати проєкт Packages...",
            "menu.save": "Зберегти",
            "menu.saveAs": "Зберегти як...",
            "menu.about": "Про Productbuilder",
            "menu.recentProjects": "Останні",
            "menu.noRecentProjects": "Немає останніх проєктів",
            "menu.clearRecentProjects": "Очистити меню",
            "menu.file": "Файл",
            "menu.edit": "Редагування",
            "menu.view": "Вигляд",
            "menu.window": "Вікно",
            "menu.help": "Довідка",
            "menu.productbuilderHelp": "Довідка Productbuilder",
            "menu.hideApp": "Сховати Productbuilder",
            "menu.hideOthers": "Сховати інші",
            "menu.showAll": "Показати всі",
            "menu.quitApp": "Завершити Productbuilder",
            "menu.close": "Закрити",
            "menu.closeWindow": "Закрити вікно",
            "menu.services": "Служби",
            "menu.noServicesApply": "Немає доступних служб",
            "menu.undo": "Скасувати",
            "menu.redo": "Повторити",
            "menu.cut": "Вирізати",
            "menu.copy": "Копіювати",
            "menu.paste": "Вставити",
            "menu.pasteAndMatchStyle": "Вставити й узгодити стиль",
            "menu.delete": "Видалити",
            "menu.selectAll": "Вибрати все",
            "menu.find": "Знайти",
            "menu.findEllipsis": "Знайти...",
            "menu.findAndReplace": "Знайти й замінити...",
            "menu.findNext": "Знайти далі",
            "menu.findPrevious": "Знайти попереднє",
            "menu.useSelectionForFind": "Використати вибране для пошуку",
            "menu.jumpToSelection": "Перейти до вибраного",
            "menu.spellingAndGrammar": "Правопис і граматика",
            "menu.showSpellingAndGrammar": "Показати правопис і граматику",
            "menu.checkDocumentNow": "Перевірити документ зараз",
            "menu.checkSpellingWhileTyping": "Перевіряти правопис під час введення",
            "menu.checkGrammarWithSpelling": "Перевіряти граматику разом із правописом",
            "menu.correctSpellingAutomatically": "Автоматично виправляти правопис",
            "menu.substitutions": "Заміни",
            "menu.showSubstitutions": "Показати заміни",
            "menu.smartCopyPaste": "Розумне копіювання/вставлення",
            "menu.smartQuotes": "Розумні лапки",
            "menu.smartDashes": "Розумні тире",
            "menu.smartLinks": "Розумні посилання",
            "menu.dataDetectors": "Детектори даних",
            "menu.textReplacement": "Заміна тексту",
            "menu.transformations": "Перетворення",
            "menu.makeUpperCase": "Зробити великими літерами",
            "menu.makeLowerCase": "Зробити малими літерами",
            "menu.capitalize": "Капіталізувати",
            "menu.speech": "Мовлення",
            "menu.startSpeaking": "Почати промовляння",
            "menu.stopSpeaking": "Зупинити промовляння",
            "menu.startDictation": "Почати диктування...",
            "menu.emojiAndSymbols": "Емодзі та символи",
            "menu.customizeTouchBar": "Налаштувати Touch Bar...",
            "menu.showToolbar": "Показати панель інструментів",
            "menu.hideToolbar": "Сховати панель інструментів",
            "menu.customizeToolbar": "Налаштувати панель інструментів...",
            "menu.showTabBar": "Показати панель вкладок",
            "menu.showAllTabs": "Показати всі вкладки",
            "menu.enterFullScreen": "Увійти в повноекранний режим",
            "menu.exitFullScreen": "Вийти з повноекранного режиму",
            "menu.minimize": "Згорнути",
            "menu.zoom": "Масштабувати",
            "menu.bringAllToFront": "Всі вікна на передній план",
            "language.menu": "Мова",
            "language.contextTitle": "Мова інтерфейсу",
            "toolbar.open": "Відкрити",
            "toolbar.open.help": "Відкрити проєкт Productbuilder",
            "toolbar.import": "Імпортувати",
            "toolbar.import.help": "Імпортувати проєкт Packages .pkgproj",
            "toolbar.save": "Зберегти",
            "toolbar.save.help": "Зберегти поточний проєкт",
            "toolbar.build": "Зібрати",
            "toolbar.build.help": "Створити інсталяційний пакет .pkg",
            "toolbar.build.running": "Збірка виконується",
            "components.title": "Компоненти",
            "components.help.label": "Довідка про компоненти",
            "components.help.tooltip": "Що таке компоненти?",
            "components.help.body": "У цьому списку показані компонентні пакети, з яких складається фінальний продукт. Додавайте окремий компонент для застосунку, допоміжного інструмента, набору ресурсів або опційної групи вмісту.",
            "components.untitled": "Компонент без назви",
            "components.add.help": "Додати компонент",
            "components.remove.help": "Видалити вибраний компонент",
            "button.add": "Додати",
            "button.remove": "Видалити",
            "button.clear": "Очистити",
            "button.continue": "Продовжити",
            "button.close": "Закрити",
            "component.selectPrompt": "Виберіть компонент.",
            "component.newName": "Компонент %d",
            "tab.component": "Компонент",
            "tab.product": "Продукт",
            "tab.design": "Оформлення",
            "tab.preview": "Перегляд",
            "section.product": "Продукт",
            "section.installerScreens": "Сторінки інсталятора",
            "section.installationRules": "Правила встановлення",
            "section.uninstaller": "Видалення",
            "section.selectedComponent": "Вибраний компонент",
            "section.preview": "Перегляд",
            "section.payload": "Вміст пакета",
            "field.name": "Назва",
            "field.identifier": "Ідентифікатор",
            "field.version": "Версія",
            "field.output": "Вихідна папка",
            "field.resources": "Ресурси інсталятора",
            "field.signing": "Підписування",
            "field.logo": "Іконка пакета",
            "field.background": "Фон",
            "field.darkBackground": "Темний фон",
            "field.scaling": "Масштабування",
            "field.alignment": "Вирівнювання",
            "field.minimumMacOS": "Мінімальна версія macOS",
            "field.customize": "Вибір компонентів",
            "field.domains": "Області встановлення",
            "field.ownership": "Власність файлів",
            "field.choice": "Пункт вибору",
            "field.preinstall": "Preinstall-скрипт",
            "field.postinstall": "Postinstall-скрипт",
            "field.destination": "Шлях призначення",
            "placeholder.productName": "Назва продукту",
            "placeholder.componentName": "Застосунок",
            "picker.ownership": "Власність файлів",
            "picker.minimumMacOS": "Мінімальна версія macOS",
            "picker.page": "Сторінка",
            "picker.localization": "Мова",
            "picker.appearance": "Вигляд",
            "picker.language": "Мова",
            "picker.payloadKind": "Тип вмісту",
            "toggle.allowCustomize": "Дозволити вибір компонентів у macOS Installer",
            "toggle.localSystem": "Для всього Mac",
            "toggle.currentUserHome": "Для поточного користувача",
            "toggle.anywhere": "Інший том або шлях",
            "toggle.generateUninstaller": "Створити shell-скрипт видалення поруч із .pkg",
            "toggle.required": "Обовʼязковий",
            "toggle.selectedByDefault": "Вибраний за замовчуванням",
            "toggle.visibleInCustomize": "Показувати у списку «Налаштувати»",
            "page.welcome": "Вітання",
            "page.readme": "Read Me",
            "page.license": "Ліцензія",
            "page.conclusion": "Завершення",
            "appearance.light": "Світлий режим",
            "appearance.dark": "Темний режим",
            "preview.page": "Сторінка",
            "preview.localization": "Мова",
            "preview.defaultLocalization": "Основна",
            "preview.appearance": "Вигляд",
            "preview.installerFallback": "Інсталятор",
            "preview.productFallback": "Продукт",
            "preview.noResource": "Для цієї сторінки ресурс не вибрано.",
            "preview.unable": "Не вдалося показати попередній перегляд %@.",
            "preview.installerTitle": "Інсталяція: %@",
            "preview.welcomeHeading": "Вас вітає Інсталятор %@",
            "preview.defaultWelcomeBody": "Ви отримаєте покрокову інструкцію з інсталювання цього програмного забезпечення.",
            "preview.step.introduction": "Вступ",
            "preview.step.destination": "Розташування",
            "preview.step.installationType": "Тип інсталяції",
            "preview.step.installation": "Інсталяція",
            "preview.step.summary": "Звіт",
            "signing.unsigned": "Без підпису",
            "signing.choose": "Вибрати ідентичність підписування",
            "signing.choose.help": "Вибрати ідентичність Developer ID Installer",
            "signing.refresh": "Оновити ідентичності",
            "signing.refresh.help": "Оновити список ідентичностей підписування",
            "buildLog.title": "Журнал збірки",
            "buildLog.clear.help": "Очистити журнал збірки",
            "buildLog.empty": "Поки що немає повідомлень збірки.",
            "buildLog.done": "Готово: %@",
            "buildLog.uninstaller": "Скрипт видалення: %@",
            "buildLog.failed": "Збірка не вдалася: %@",
            "recent.missing": "Останній проєкт не знайдено: %@",
            "scaling.proportional": "Пропорційно",
            "scaling.toFit": "Вписати",
            "scaling.none": "Без масштабування",
            "alignment.center": "По центру",
            "alignment.top": "Зверху",
            "alignment.topLeft": "Зверху ліворуч",
            "alignment.topRight": "Зверху праворуч",
            "alignment.left": "Ліворуч",
            "alignment.bottom": "Знизу",
            "alignment.bottomLeft": "Знизу ліворуч",
            "alignment.bottomRight": "Знизу праворуч",
            "alignment.right": "Праворуч",
            "ownership.recommended": "Рекомендовано",
            "ownership.preserve": "Зберегти з джерела",
            "payload.fileFolder": "Файл або папка",
            "payload.fileOrFolder": "Файл або папка",
            "payload.folderContents": "Вміст папки",
            "payload.emptyDirectory": "Порожня папка",
            "payload.add": "Додати вміст",
            "payload.add.help": "Додати запис вмісту пакета",
            "payload.remove.help": "Видалити запис вмісту пакета",
            "payload.empty": "Вміст пакета ще не задано. Додайте файл, вміст папки або порожню папку.",
            "localization.title": "Мовні версії",
            "localization.add": "Додати мову",
            "localization.add.help": "Додати мовну версію",
            "localization.remove.help": "Видалити мовну версію",
            "localization.language.help": "Вибрати мову для цієї сторінки інсталятора",
            "macos.noMinimum": "Без мінімальної версії",
            "macos.custom": "Власне значення: %@",
            "macos.help": "Виберіть найстарішу версію macOS, на якій дозволено встановлення продукту.",
            "path.optional": "Не вказано",
            "path.choosePath": "Вибір шляху",
            "path.choose": "Вибрати",
            "path.choose.help": "Вибрати шлях",
            "path.chooseOptional.help": "Вибрати шлях, якщо цей ресурс потрібен",
            "about.credits": "Інструмент для створення macOS product .pkg інсталяторів із компонентів, вмісту пакета, ресурсів інсталятора, локалізованих сторінок, налаштувань підписування та опційного скрипта видалення.",
            "help.window.title": "Довідка Productbuilder",
            "help.window.subtitle": "Короткий практичний довідник по можливостях додатка та налаштуваннях інсталятора.",
            "help.overview.title": "Що робить Productbuilder",
            "help.overview.body": "Productbuilder створює macOS product .pkg інсталятори. Він може збирати компонентні пакети, обʼєднувати їх у product package, імпортувати проєкти Packages .pkgproj, налаштовувати файли й папки вмісту, готувати ресурси інсталятора, показувати попередній перегляд сторінок, підписувати результат і створювати супровідний скрипт видалення.",
            "help.overview.workflow": "Типовий процес: додати компоненти, описати вміст кожного компонента, налаштувати метадані продукту, додати сторінки інсталятора та мовні версії, перевірити перегляд, вибрати підписування і зібрати фінальний .pkg.",
            "help.about": "Довідка: %@",
            "help.product.name": "Назва: відображувана назва кінцевого інсталятора.",
            "help.product.identifier": "Ідентифікатор: id продукту у форматі reverse-DNS для receipt macOS Installer.",
            "help.product.version": "Версія: версія продукту, яку буде записано у згенерований пакет.",
            "help.product.output": "Вихідна папка: місце, де буде створено кінцевий .pkg і, за потреби, скрипт видалення.",
            "help.product.resources": "Ресурси інсталятора: необовʼязкова папка з файлами, на які посилається Distribution XML.",
            "help.product.signing": "Підписування: ідентичність Developer ID Installer для підписування кінцевого product package.",
            "help.design.logo": "Іконка пакета: необовʼязкове зображення для кінцевого .pkg і заголовка вікна macOS Installer.",
            "help.design.background": "Фон і темний фон: зображення для вікна macOS Installer. Якщо темний фон не задано, звичайний фон використовується і для світлого, і для темного режиму.",
            "help.design.scaling": "Масштабування і вирівнювання: як фонове зображення розміщується у вікні інсталятора.",
            "help.design.pages": "Вітання, Read Me, Ліцензія, Завершення: сторінки інсталятора, які копіюються в ресурси і згадуються в Distribution XML.",
            "help.design.localizations": "Мовні версії: локалізовані варіанти сторінок, які записуються в папки .lproj.",
            "help.rules.minimum": "Мінімальна версія macOS: необовʼязкова вимога до системи, без якої інсталятор не запуститься.",
            "help.rules.customize": "Вибір компонентів: дозволяє користувачу відкривати список «Налаштувати» і змінювати видимі опційні компоненти.",
            "help.rules.localSystem": "Для всього Mac: встановлення в системну область, типовий режим для /Applications і /Library.",
            "help.rules.currentUserHome": "Для поточного користувача: дозволяє встановлення в домашню область вибраного користувача.",
            "help.rules.anywhere": "Інший том або шлях: дозволяє вибрати інший том або шлях призначення, якщо macOS Installer це підтримує.",
            "help.uninstaller.generate": "Створити shell-скрипт видалення: створює супровідний скрипт поруч із кінцевим .pkg.",
            "help.uninstaller.removes": "Скрипт видаляє встановлені файли з вмісту пакета, які Productbuilder може безпечно відстежити під час збірки.",
            "help.uninstaller.emptyDirs": "Порожні папки створюються інсталятором, але згенерований скрипт видалення не прибирає їх примусово.",
            "help.ownership.short": "Рекомендовано дозволяє pkgbuild застосувати рекомендованих власника і групу. «Зберегти з джерела» бере їх із вихідних файлів.",
            "help.choice.required": "Користувач не може вимкнути цей компонент у macOS Installer. Обовʼязкові компоненти завжди вибрані.",
            "help.choice.selected": "Компонент буде вибраний, коли користувач відкриє список «Налаштувати».",
            "help.choice.visible": "Показувати цей компонент у списку «Налаштувати» в macOS Installer.",
            "help.component.name": "Назва: підпис компонента в Productbuilder і у списку вибору компонентів інсталятора.",
            "help.component.identifier": "Ідентифікатор: id у форматі reverse-DNS для receipt пакета цього компонента.",
            "help.component.version": "Версія: версія компонентного пакета, яку буде передано в pkgbuild.",
            "help.component.ownership": "Власність файлів: «Рекомендовано» дозволяє pkgbuild застосувати рекомендованих власника і групу; «Зберегти з джерела» бере їх із вихідних файлів.",
            "help.component.choice": "Пункт вибору: визначає, чи компонент обовʼязковий, вибраний за замовчуванням і видимий у списку «Налаштувати».",
            "help.component.scripts": "Preinstall- і Postinstall-скрипти: необовʼязкові shell-скрипти, які виконує пакет цього компонента.",
            "help.preview.page": "Сторінка: вибирає сторінку інсталятора для попереднього перегляду.",
            "help.preview.localization": "Мова: показує основний ресурс або локалізований варіант із папки .lproj.",
            "help.preview.appearance": "Вигляд: перемикає світлий і темний варіанти оформлення.",
            "help.preview.approximate": "Попередній перегляд є приблизним; остаточне компонування виконує macOS Installer.",
            "help.payload.fileFolder": "Файл або папка: копіює вибраний файл або саму папку в шлях призначення.",
            "help.payload.folderContents": "Вміст папки: копіює поточний вміст вихідної папки у фіксовану папку призначення під час збірки.",
            "help.payload.emptyDirectory": "Порожня папка: створює папку призначення без вихідного шляху.",
            "help.payload.destination": "Шлях призначення: абсолютний шлях, куди буде підготовлено цей запис вмісту пакета.",
            "installerLanguage.en": "Англійська",
            "installerLanguage.uk": "Українська",
            "installerLanguage.es": "Іспанська",
            "installerLanguage.fr": "Французька",
            "installerLanguage.de": "Німецька",
            "installerLanguage.it": "Італійська",
            "installerLanguage.pt_BR": "Португальська",
            "installerLanguage.pl": "Польська",
            "installerLanguage.ru": "Російська",
            "installerLanguage.zh_CN": "Китайська (спрощена)",
            "installerLanguage.zh_TW": "Китайська (традиційна)",
            "installerLanguage.ja": "Японська",
            "installerLanguage.ko": "Корейська",
            "installerLanguage.nl": "Нідерландська",
            "installerLanguage.tr": "Турецька",
            "installerLanguage.custom": "Власна"
        ]
    ]
}
