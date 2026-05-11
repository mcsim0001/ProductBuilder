import AppKit
import SwiftUI

private enum ConfigurationTab: Hashable {
    case component
    case product
    case installer
    case preview
}

struct ContentView: View {
    @EnvironmentObject private var model: PackageProjectModel
    @EnvironmentObject private var localization: AppLocalization
    @State private var signingIdentities: [String] = []
    @State private var showsComponentsHelp = false
    @State private var selectedConfigurationTab: ConfigurationTab = .component

    var body: some View {
        NavigationSplitView {
            componentSidebar
        } detail: {
            HSplitView {
                configurationView
                    .frame(minWidth: 520)

                logView
                    .frame(minWidth: 320)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    ProjectDocument.open(into: model)
                } label: {
                    Label(localization.t("toolbar.open"), systemImage: "folder")
                }
                .help(localization.t("toolbar.open.help"))

                Button {
                    ProjectDocument.importPackagesProject(into: model)
                } label: {
                    Label(localization.t("toolbar.import"), systemImage: "square.and.arrow.down.on.square")
                }
                .help(localization.t("toolbar.import.help"))

                Button {
                    ProjectDocument.save(model)
                } label: {
                    Label(localization.t("toolbar.save"), systemImage: "square.and.arrow.down")
                }
                .help(localization.t("toolbar.save.help"))

                Button {
                    build()
                } label: {
                    Label(localization.t("toolbar.build"), systemImage: "hammer")
                }
                .disabled(model.isBuilding)
                .help(model.isBuilding ? localization.t("toolbar.build.running") : localization.t("toolbar.build.help"))
            }
        }
        .contextMenu {
            languageMenuItems
        }
        .onAppear {
            model.selectFirstComponentIfNeeded()
            refreshSigningIdentities()
        }
    }

    @ViewBuilder
    private var languageMenuItems: some View {
        Text(localization.t("language.contextTitle"))
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

    private var componentSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(localization.t("components.title"))
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    showsComponentsHelp.toggle()
                } label: {
                    Label(localization.t("components.help.label"), systemImage: "questionmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(localization.t("components.help.tooltip"))
                .popover(isPresented: $showsComponentsHelp, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localization.t("components.title"))
                            .font(.headline)
                        Text(localization.t("components.help.body"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 280, alignment: .leading)
                    .padding(14)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            List(selection: $model.selectedComponentID) {
                ForEach(model.project.components) { component in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(component.name.isEmpty ? localization.t("components.untitled") : component.name)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(component.packageIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .tag(component.id)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Button {
                    let component = PackageComponent(
                        name: localization.t("component.newName", model.project.components.count + 1),
                        packageIdentifier: suggestedComponentIdentifier()
                    )
                    model.project.components.append(component)
                    model.selectedComponentID = component.id
                } label: {
                    Label(localization.t("button.add"), systemImage: "plus")
                }
                .fixedSize()
                .help(localization.t("components.add.help"))

                Button {
                    removeSelectedComponent()
                } label: {
                    Label(localization.t("button.remove"), systemImage: "minus")
                }
                .disabled(model.project.components.count <= 1)
                .fixedSize()
                .help(localization.t("components.remove.help"))

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .navigationTitle(localization.t("components.title"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .navigationSplitViewColumnWidth(
            min: 260,
            ideal: 300,
            max: 420
        )
    }

    private var configurationView: some View {
        TabView(selection: $selectedConfigurationTab) {
            configurationTabContent {
                if model.selectedComponent != nil {
                    componentSection
                } else {
                    Text(localization.t("component.selectPrompt"))
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem {
                Label(localization.t("tab.component"), systemImage: "shippingbox")
            }
            .tag(ConfigurationTab.component)

            configurationTabContent {
                productSection
                installationSection
                uninstallerSection
            }
            .tabItem {
                Label(localization.t("tab.product"), systemImage: "cube.box")
            }
            .tag(ConfigurationTab.product)

            configurationTabContent {
                presentationSection
            }
            .tabItem {
                Label(localization.t("tab.design"), systemImage: "rectangle.inset.filled")
            }
            .tag(ConfigurationTab.installer)

            configurationTabContent {
                InstallerPreviewView(project: model.project)
            }
            .tabItem {
                Label(localization.t("tab.preview"), systemImage: "eye")
            }
            .tag(ConfigurationTab.preview)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedComponentID) { _ in
            selectedConfigurationTab = .component
        }
    }

    private func configurationTabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var productSection: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(localization.t("field.name"))
                    TextField(localization.t("placeholder.productName"), text: $model.project.productName)
                }

                GridRow {
                    Text(localization.t("field.identifier"))
                    TextField("com.example.product", text: $model.project.productIdentifier)
                }

                GridRow {
                    Text(localization.t("field.version"))
                    TextField("1.0.0", text: $model.project.productVersion)
                        .frame(maxWidth: 160)
                }

                GridRow {
                    Text(localization.t("field.output"))
                    PathField(path: $model.project.outputDirectory, mode: .directory)
                }

                GridRow {
                    Text(localization.t("field.resources"))
                    PathField(path: $model.project.resourcesDirectory, mode: .directory, optional: true)
                }

                GridRow {
                    Text(localization.t("field.signing"))
                    signingIdentityField
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)
        } label: {
            SectionHelpHeader(
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
        }
    }

    private var presentationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                visualBrandingSection

                Divider()

                InstallerPageResourceEditor(
                    title: localization.t("page.welcome"),
                    defaultPath: $model.project.welcomePath,
                    localizations: $model.project.welcomeLocalizations
                )

                Divider()

                InstallerPageResourceEditor(
                    title: localization.t("page.readme"),
                    defaultPath: $model.project.readmePath,
                    localizations: $model.project.readmeLocalizations
                )

                Divider()

                InstallerPageResourceEditor(
                    title: localization.t("page.license"),
                    defaultPath: $model.project.licensePath,
                    localizations: $model.project.licenseLocalizations
                )

                Divider()

                InstallerPageResourceEditor(
                    title: localization.t("page.conclusion"),
                    defaultPath: $model.project.conclusionPath,
                    localizations: $model.project.conclusionLocalizations
                )
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)
        } label: {
            SectionHelpHeader(
                title: localization.t("section.installerScreens"),
                lines: [
                    localization.t("help.design.logo"),
                    localization.t("help.design.background"),
                    localization.t("help.design.scaling"),
                    localization.t("help.design.pages"),
                    localization.t("help.design.localizations")
                ]
            )
        }
    }

    private var visualBrandingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text(localization.t("field.logo"))
                    PathField(path: $model.project.logoPath, mode: .file, optional: true)
                }

                GridRow {
                    Text(localization.t("field.background"))
                    PathField(path: $model.project.backgroundPath, mode: .file, optional: true)
                }

                GridRow {
                    Text(localization.t("field.darkBackground"))
                    PathField(path: $model.project.darkBackgroundPath, mode: .file, optional: true)
                }

                GridRow {
                    Text(localization.t("field.scaling"))
                    Picker(localization.t("field.scaling"), selection: $model.project.backgroundScaling) {
                        ForEach(InstallerBackgroundScaling.allCases) { scaling in
                            Text(scaling.localizedTitle(localization)).tag(scaling)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                GridRow {
                    Text(localization.t("field.alignment"))
                    Picker(localization.t("field.alignment"), selection: $model.project.backgroundAlignment) {
                        ForEach(InstallerBackgroundAlignment.allCases) { alignment in
                            Text(alignment.localizedTitle(localization)).tag(alignment)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
        }
    }

    private var installationSection: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(localization.t("field.minimumMacOS"))
                    MacOSVersionPicker(selection: $model.project.minimumSystemVersion)
                        .frame(maxWidth: 260)
                }

                GridRow {
                    Text(localization.t("field.customize"))
                    Toggle(localization.t("toggle.allowCustomize"), isOn: $model.project.allowCustomize)
                }

                GridRow {
                    Text(localization.t("field.domains"))
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(localization.t("toggle.localSystem"), isOn: $model.project.enableLocalSystemDomain)
                        Toggle(localization.t("toggle.currentUserHome"), isOn: $model.project.enableCurrentUserHomeDomain)
                        Toggle(localization.t("toggle.anywhere"), isOn: $model.project.enableAnywhereDomain)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)
        } label: {
            SectionHelpHeader(
                title: localization.t("section.installationRules"),
                lines: [
                    localization.t("help.rules.minimum"),
                    localization.t("help.rules.customize"),
                    localization.t("help.rules.localSystem"),
                    localization.t("help.rules.currentUserHome"),
                    localization.t("help.rules.anywhere")
                ]
            )
        }
    }

    private var uninstallerSection: some View {
        GroupBox {
            HStack {
                Toggle(localization.t("toggle.generateUninstaller"), isOn: $model.project.generateUninstaller)
                Spacer()
                Text(model.project.uninstallerFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        } label: {
            SectionHelpHeader(
                title: localization.t("section.uninstaller"),
                lines: [
                    localization.t("help.uninstaller.generate"),
                    localization.t("help.uninstaller.removes"),
                    localization.t("help.uninstaller.emptyDirs")
                ]
            )
        }
    }

    private var componentSection: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(localization.t("field.name"))
                    TextField(
                        localization.t("placeholder.componentName"),
                        text: binding(\.name)
                    )
                }

                GridRow {
                    Text(localization.t("field.identifier"))
                    TextField("com.example.product.app", text: binding(\.packageIdentifier))
                }

                GridRow {
                    Text(localization.t("field.version"))
                    TextField("1.0.0", text: binding(\.version))
                        .frame(maxWidth: 160)
                }

                GridRow {
                    Text(localization.t("field.ownership"))
                    Picker(localization.t("picker.ownership"), selection: binding(\.ownership)) {
                        ForEach(OwnershipMode.allCases) { mode in
                            Text(mode.localizedTitle(localization)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .help(localization.t("help.ownership.short"))
                }

                GridRow {
                    Text(localization.t("field.choice"))
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(localization.t("toggle.required"), isOn: requiredChoiceBinding)
                            .help(localization.t("help.choice.required"))
                        Toggle(localization.t("toggle.selectedByDefault"), isOn: binding(\.isSelected))
                            .disabled(model.selectedComponent?.isRequired == true)
                            .help(localization.t("help.choice.selected"))
                        Toggle(localization.t("toggle.visibleInCustomize"), isOn: binding(\.isVisible))
                            .help(localization.t("help.choice.visible"))
                    }
                }

                GridRow {
                    Text(localization.t("field.preinstall"))
                    PathField(path: binding(\.preinstallScriptPath), mode: .file, optional: true)
                }

                GridRow {
                    Text(localization.t("field.postinstall"))
                    PathField(path: binding(\.postinstallScriptPath), mode: .file, optional: true)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)

            Divider()
                .padding(.horizontal, 12)

            PayloadEntriesEditor(entries: binding(\.payloadEntries))
                .padding(12)
        } label: {
            SectionHelpHeader(
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
        }
    }

    private var signingIdentityField: some View {
        HStack(spacing: 8) {
            TextField("Developer ID Installer: ...", text: $model.project.signingIdentity)

            Menu {
                Button(localization.t("signing.unsigned")) {
                    model.project.signingIdentity = ""
                }

                if !signingIdentities.isEmpty {
                    Divider()
                }

                ForEach(signingIdentities, id: \.self) { identity in
                    Button(identity) {
                        model.project.signingIdentity = identity
                    }
                }
            } label: {
                Label(localization.t("signing.choose"), systemImage: "checkmark.seal")
                    .labelStyle(.iconOnly)
            }
            .help(localization.t("signing.choose.help"))

            Button {
                refreshSigningIdentities()
            } label: {
                Label(localization.t("signing.refresh"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help(localization.t("signing.refresh.help"))
        }
    }

    private var logView: some View {
        VStack(spacing: 0) {
            HStack {
                Label(localization.t("buildLog.title"), systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if model.isBuilding {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Button {
                    model.log = ""
                } label: {
                    Label(localization.t("button.clear"), systemImage: "trash")
                }
                .help(localization.t("buildLog.clear.help"))
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.log.isEmpty ? localization.t("buildLog.empty") : model.log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(model.log.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)

                    Color.clear
                        .frame(height: 1)
                        .id("buildLogBottom")
                }
                .onChange(of: model.log) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("buildLogBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PackageComponent, Value>) -> Binding<Value> {
        Binding {
            model.selectedComponent?[keyPath: keyPath] ?? PackageComponent()[keyPath: keyPath]
        } set: { newValue in
            model.updateSelectedComponent { component in
                component[keyPath: keyPath] = newValue
            }
        }
    }

    private var requiredChoiceBinding: Binding<Bool> {
        Binding {
            model.selectedComponent?.isRequired ?? true
        } set: { newValue in
            model.updateSelectedComponent { component in
                component.isRequired = newValue
                if newValue {
                    component.isSelected = true
                }
            }
        }
    }

    private func suggestedComponentIdentifier() -> String {
        let base = model.project.productIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = model.project.components.count + 1
        return base.isEmpty ? "com.example.component\(suffix)" : "\(base).component\(suffix)"
    }

    private func removeSelectedComponent() {
        guard let selected = model.selectedComponentID,
              let index = model.project.components.firstIndex(where: { $0.id == selected }),
              model.project.components.count > 1 else {
            return
        }
        model.project.components.remove(at: index)
        model.selectFirstComponentIfNeeded()
    }

    private func build() {
        model.isBuilding = true
        model.log = ""

        let project = model.project
        Task {
            do {
                let result = try await PackageBuildService().build(project: project) { message in
                    model.appendLog(message)
                }
                model.appendLog(localization.t("buildLog.done", result.outputURL.path))
                if let uninstallerURL = result.uninstallerURL {
                    model.appendLog(localization.t("buildLog.uninstaller", uninstallerURL.path))
                }
            } catch {
                model.appendLog(localization.t("buildLog.failed", error.localizedDescription))
            }
            model.isBuilding = false
        }
    }

    private func refreshSigningIdentities() {
        Task {
            let identities = await Task.detached {
                SigningIdentityProvider.load()
            }.value
            signingIdentities = identities
        }
    }
}

private struct InstallerPreviewView: View {
    @EnvironmentObject private var localization: AppLocalization
    let project: PackageProject
    @State private var page: InstallerPreviewPage = .welcome
    @State private var languageCode: String = ""
    @State private var appearance: InstallerPreviewAppearance = .light

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewControls

            InstallerWindowPreview(
                project: project,
                page: page,
                languageCode: languageCode,
                appearance: appearance
            )
            .frame(maxWidth: 860)
        }
        .onChange(of: page) { _ in
            normalizeLanguageSelection()
        }
        .onChange(of: project) { _ in
            normalizeLanguageSelection()
        }
    }

    private var previewControls: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(localization.t("preview.page"))
                    Picker(localization.t("picker.page"), selection: $page) {
                        ForEach(InstallerPreviewPage.allCases) { page in
                            Text(page.localizedTitle(localization)).tag(page)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                GridRow {
                    Text(localization.t("preview.localization"))
                    Picker(localization.t("picker.localization"), selection: $languageCode) {
                        Text(localization.t("preview.defaultLocalization")).tag("")
                        ForEach(languageCodes, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                GridRow {
                    Text(localization.t("preview.appearance"))
                    Picker(localization.t("picker.appearance"), selection: $appearance) {
                        ForEach(InstallerPreviewAppearance.allCases) { appearance in
                            Text(appearance.localizedTitle(localization)).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }
            .padding(12)
        } label: {
            SectionHelpHeader(
                title: localization.t("section.preview"),
                lines: [
                    localization.t("help.preview.page"),
                    localization.t("help.preview.localization"),
                    localization.t("help.preview.appearance"),
                    localization.t("help.preview.approximate")
                ]
            )
        }
    }

    private var languageCodes: [String] {
        page.localizations(in: project)
            .map(\.previewLanguageCode)
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func normalizeLanguageSelection() {
        if !languageCode.isEmpty && !languageCodes.contains(languageCode) {
            languageCode = ""
        }
    }
}

private struct InstallerWindowPreview: View {
    @EnvironmentObject private var localization: AppLocalization
    let project: PackageProject
    let page: InstallerPreviewPage
    let languageCode: String
    let appearance: InstallerPreviewAppearance

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ZStack {
                backgroundLayer

                HStack(spacing: 0) {
                    stepSidebar
                        .frame(width: 190)

                    Rectangle()
                        .fill(Color(nsColor: style.dividerColor))
                        .frame(width: 1)

                    contentPane
                }
            }
        }
        .frame(height: 430)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: style.windowBorderColor), lineWidth: 1)
        }
    }

    private var selectedPath: String {
        page.path(in: project, languageCode: languageCode)
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color.red.opacity(0.9)).frame(width: 12, height: 12)
                Circle().fill(Color.yellow.opacity(0.9)).frame(width: 12, height: 12)
                Circle().fill(Color(nsColor: .tertiaryLabelColor)).frame(width: 12, height: 12)
            }
            .frame(width: 82, alignment: .leading)

            Spacer()

            HStack(spacing: 6) {
                packageIcon
                    .frame(width: 18, height: 18)

                Text(localization.t("preview.installerTitle", displayProductName))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: style.titleTextColor))
                    .lineLimit(1)
            }

            Spacer()
            Color.clear.frame(width: 82, height: 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color(nsColor: style.titleBarColor))
    }

    @ViewBuilder
    private var packageIcon: some View {
        if let logoImage {
            Image(nsImage: logoImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "shippingbox.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let image = backgroundImage {
            ZStack {
                Color(nsColor: style.windowBodyColor)
                InstallerBackgroundImage(
                    image: image,
                    scaling: project.backgroundScaling,
                    alignment: project.backgroundAlignment
                )
            }
        } else {
            Color(nsColor: style.windowBodyColor)
        }
    }

    private var stepSidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(previewSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(nsColor: index == selectedStepIndex ? style.stepDotActiveColor : style.stepDotInactiveColor))
                        .frame(width: 10, height: 10)

                    Text(step)
                        .font(.headline.weight(index == selectedStepIndex ? .semibold : .regular))
                        .foregroundStyle(Color(nsColor: index == selectedStepIndex ? style.stepTextActiveColor : style.stepTextInactiveColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()
        }
        .padding(.top, 66)
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: style.sidebarColor).opacity(backgroundImage == nil ? 1 : 0.82))
    }

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pageHeading)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(nsColor: style.headingTextColor))
                .lineLimit(2)

            InstallerDocumentPreview(
                path: selectedPath,
                fallbackMessage: defaultPageMessage,
                style: style
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Rectangle()
                        .stroke(Color(nsColor: style.documentBorderColor), lineWidth: 1)
                }

            HStack {
                Spacer()
                InstallerPreviewButton(title: localization.t("button.continue"), style: style)
            }
        }
        .padding(.top, 24)
        .padding(.leading, 30)
        .padding(.trailing, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(contentBackground)
    }

    private var previewSteps: [String] {
        var steps = [localization.t("preview.step.introduction")]
        if hasResource(for: .readme) || page == .readme {
            steps.append(localization.t("page.readme"))
        }
        if hasResource(for: .license) || page == .license {
            steps.append(localization.t("page.license"))
        }
        steps.append(contentsOf: [
            localization.t("preview.step.destination"),
            localization.t("preview.step.installationType"),
            localization.t("preview.step.installation"),
            localization.t("preview.step.summary")
        ])
        return steps
    }

    private var selectedStepIndex: Int {
        switch page {
        case .welcome:
            return 0
        case .readme:
            return hasResource(for: .readme) || page == .readme ? 1 : 0
        case .license:
            var index = 1
            if hasResource(for: .readme) {
                index += 1
            }
            return index
        case .conclusion:
            return previewSteps.count - 1
        }
    }

    private var pageHeading: String {
        switch page {
        case .welcome:
            return localization.t("preview.welcomeHeading", displayProductName)
        case .readme, .license, .conclusion:
            return page.localizedTitle(localization)
        }
    }

    private var defaultPageMessage: String? {
        guard selectedPath.trimmed.isEmpty, page == .welcome else { return nil }
        return localization.t("preview.defaultWelcomeBody")
    }

    private var displayProductName: String {
        project.productName.isEmpty ? localization.t("preview.productFallback") : project.productName
    }

    private func hasResource(for page: InstallerPreviewPage) -> Bool {
        !page.path(in: project, languageCode: languageCode).trimmed.isEmpty
            || !page.localizations(in: project).isEmpty
    }

    private var contentBackground: Color {
        if backgroundImage == nil {
            Color(nsColor: style.contentColor)
        } else {
            Color(nsColor: style.contentColor).opacity(0.08)
        }
    }

    private var backgroundImage: NSImage? {
        let path = appearance == .dark && !project.darkBackgroundPath.trimmed.isEmpty
            ? project.darkBackgroundPath
            : project.backgroundPath
        return NSImage(contentsOfFile: path)
    }

    private var logoImage: NSImage? {
        NSImage(contentsOfFile: project.logoPath)
    }

    private var style: InstallerPreviewStyle {
        InstallerPreviewStyle(appearance: appearance)
    }
}

private struct InstallerPreviewButton: View {
    let title: String
    let style: InstallerPreviewStyle

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color(nsColor: style.disabledButtonTextColor))
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: style.disabledButtonColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: style.disabledButtonBorderColor), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct InstallerBackgroundImage: View {
    let image: NSImage
    let scaling: InstallerBackgroundScaling
    let alignment: InstallerBackgroundAlignment

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: alignment.swiftUIAlignment) {
                Color.clear

                Image(nsImage: image)
                    .resizable()
                    .frame(width: imageSize(in: geometry.size).width, height: imageSize(in: geometry.size).height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private func imageSize(in containerSize: CGSize) -> CGSize {
        switch scaling {
        case .proportional:
            guard image.size.width > 0, image.size.height > 0, containerSize.width > 0, containerSize.height > 0 else {
                return containerSize
            }
            let scale = min(1, containerSize.width / image.size.width, containerSize.height / image.size.height)
            return CGSize(width: image.size.width * scale, height: image.size.height * scale)
        case .tofit:
            return containerSize
        case .none:
            return image.size
        }
    }
}

private struct InstallerDocumentPreview: View {
    @EnvironmentObject private var localization: AppLocalization
    let path: String
    var fallbackMessage: String? = nil
    let style: InstallerPreviewStyle

    var body: some View {
        if path.trimmed.isEmpty, let fallbackMessage {
            fallbackView(fallbackMessage)
        } else if path.trimmed.isEmpty {
            missingView(localization.t("preview.noResource"))
        } else if let attributedString = attributedString {
            AttributedTextView(
                attributedString: attributedString,
                textColor: style.documentTextColor,
                backgroundColor: style.documentBackgroundColor
            )
        } else {
            missingView(localization.t("preview.unable", URL(fileURLWithPath: path).lastPathComponent))
        }
    }

    private var attributedString: NSAttributedString? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            switch url.pathExtension.lowercased() {
            case "html", "htm":
                let data = try Data(contentsOf: url)
                return try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue,
                        .baseURL: url.deletingLastPathComponent()
                    ],
                    documentAttributes: nil
                )
            case "rtf":
                let data = try Data(contentsOf: url)
                return try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
            case "rtfd":
                return try NSAttributedString(
                    url: url,
                    options: [.documentType: NSAttributedString.DocumentType.rtfd],
                    documentAttributes: nil
                )
            default:
                let text = try String(contentsOf: url, encoding: .utf8)
                return NSAttributedString(string: text)
            }
        } catch {
            return nil
        }
    }

    private func missingView(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(secondaryTextColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(documentBackgroundColor)
    }

    private func fallbackView(_ message: String) -> some View {
        Text(message)
            .font(.title3.weight(.semibold))
            .foregroundStyle(primaryTextColor)
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(documentBackgroundColor)
    }

    private var primaryTextColor: Color {
        Color(nsColor: style.documentTextColor)
    }

    private var secondaryTextColor: Color {
        Color(nsColor: style.documentSecondaryTextColor)
    }

    private var documentBackgroundColor: Color {
        Color(nsColor: style.documentBackgroundColor)
    }
}

private struct AttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let textColor: NSColor
    let backgroundColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.textColor = textColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame = scrollView.contentView.bounds
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        scrollView.backgroundColor = backgroundColor
        textView.backgroundColor = backgroundColor
        textView.textColor = textColor
        textView.frame = scrollView.contentView.bounds
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedString.withPreviewTextColor(textColor))
    }
}

private extension NSAttributedString {
    func withPreviewTextColor(_ color: NSColor) -> NSAttributedString {
        let styledString = NSMutableAttributedString(attributedString: self)
        let fullRange = NSRange(location: 0, length: styledString.length)
        guard fullRange.length > 0 else { return styledString }
        styledString.addAttribute(.foregroundColor, value: color, range: fullRange)
        return styledString
    }
}

private struct InstallerPreviewStyle {
    let appearance: InstallerPreviewAppearance

    var titleBarColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.93, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.20, alpha: 1)
        }
    }

    var windowBodyColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.94, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.14, alpha: 1)
        }
    }

    var sidebarColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.91, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.12, alpha: 1)
        }
    }

    var contentColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.94, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.14, alpha: 1)
        }
    }

    var documentBackgroundColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 1, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.11, alpha: 1)
        }
    }

    var windowBorderColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.78, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.30, alpha: 1)
        }
    }

    var dividerColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.78, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.27, alpha: 1)
        }
    }

    var documentBorderColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.88, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.29, alpha: 1)
        }
    }

    var titleTextColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.42, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.72, alpha: 1)
        }
    }

    var headingTextColor: NSColor {
        documentTextColor
    }

    var documentTextColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.10, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.96, alpha: 1)
        }
    }

    var documentSecondaryTextColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.48, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.62, alpha: 1)
        }
    }

    var stepTextActiveColor: NSColor {
        documentTextColor
    }

    var stepTextInactiveColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.48, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.62, alpha: 1)
        }
    }

    var stepDotActiveColor: NSColor {
        NSColor.systemBlue
    }

    var stepDotInactiveColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.58, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.42, alpha: 1)
        }
    }

    var disabledButtonColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.96, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.30, alpha: 1)
        }
    }

    var disabledButtonTextColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.72, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.64, alpha: 1)
        }
    }

    var disabledButtonBorderColor: NSColor {
        switch appearance {
        case .light:
            return NSColor(calibratedWhite: 0.86, alpha: 1)
        case .dark:
            return NSColor(calibratedWhite: 0.34, alpha: 1)
        }
    }
}

private enum InstallerPreviewPage: String, CaseIterable, Identifiable {
    case welcome
    case readme
    case license
    case conclusion

    var id: String { rawValue }

    @MainActor
    func localizedTitle(_ localization: AppLocalization) -> String {
        switch self {
        case .welcome:
            return localization.t("page.welcome")
        case .readme:
            return localization.t("page.readme")
        case .license:
            return localization.t("page.license")
        case .conclusion:
            return localization.t("page.conclusion")
        }
    }

    func path(in project: PackageProject, languageCode: String) -> String {
        if !languageCode.isEmpty,
           let localization = localizations(in: project).first(where: { $0.previewLanguageCode == languageCode }) {
            return localization.path
        }

        switch self {
        case .welcome:
            return project.welcomePath
        case .readme:
            return project.readmePath
        case .license:
            return project.licensePath
        case .conclusion:
            return project.conclusionPath
        }
    }

    func localizations(in project: PackageProject) -> [LocalizedInstallerResource] {
        switch self {
        case .welcome:
            return project.welcomeLocalizations
        case .readme:
            return project.readmeLocalizations
        case .license:
            return project.licenseLocalizations
        case .conclusion:
            return project.conclusionLocalizations
        }
    }
}

private enum InstallerPreviewAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    @MainActor
    func localizedTitle(_ localization: AppLocalization) -> String {
        switch self {
        case .light:
            return localization.t("appearance.light")
        case .dark:
            return localization.t("appearance.dark")
        }
    }
}

private extension InstallerBackgroundAlignment {
    var swiftUIAlignment: Alignment {
        switch self {
        case .center:
            return .center
        case .top:
            return .top
        case .topleft:
            return .topLeading
        case .topright:
            return .topTrailing
        case .left:
            return .leading
        case .bottom:
            return .bottom
        case .bottomleft:
            return .bottomLeading
        case .bottomright:
            return .bottomTrailing
        case .right:
            return .trailing
        }
    }
}

private extension InstallerBackgroundScaling {
    @MainActor
    func localizedTitle(_ localization: AppLocalization) -> String {
        switch self {
        case .proportional:
            return localization.t("scaling.proportional")
        case .tofit:
            return localization.t("scaling.toFit")
        case .none:
            return localization.t("scaling.none")
        }
    }
}

private extension InstallerBackgroundAlignment {
    @MainActor
    func localizedTitle(_ localization: AppLocalization) -> String {
        switch self {
        case .center:
            return localization.t("alignment.center")
        case .top:
            return localization.t("alignment.top")
        case .topleft:
            return localization.t("alignment.topLeft")
        case .topright:
            return localization.t("alignment.topRight")
        case .left:
            return localization.t("alignment.left")
        case .bottom:
            return localization.t("alignment.bottom")
        case .bottomleft:
            return localization.t("alignment.bottomLeft")
        case .bottomright:
            return localization.t("alignment.bottomRight")
        case .right:
            return localization.t("alignment.right")
        }
    }
}

private extension OwnershipMode {
    @MainActor
    func localizedTitle(_ localization: AppLocalization) -> String {
        switch self {
        case .recommended:
            return localization.t("ownership.recommended")
        case .preserve:
            return localization.t("ownership.preserve")
        }
    }
}

private extension PackagePayloadKind {
    @MainActor
    func localizedTitle(_ localization: AppLocalization) -> String {
        switch self {
        case .fileOrFolder:
            return localization.t("payload.fileFolder")
        case .folderContents:
            return localization.t("payload.folderContents")
        case .emptyDirectory:
            return localization.t("payload.emptyDirectory")
        }
    }
}

private extension LocalizedInstallerResource {
    var previewLanguageCode: String {
        var code = languageCode.trimmed
        if code.hasSuffix(".lproj") {
            code.removeLast(".lproj".count)
        }
        return code
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private struct PayloadEntriesEditor: View {
    @EnvironmentObject private var localization: AppLocalization
    @Binding var entries: [PackagePayloadEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHelpHeader(
                    title: localization.t("section.payload"),
                    lines: [
                        localization.t("help.payload.fileFolder"),
                        localization.t("help.payload.folderContents"),
                        localization.t("help.payload.emptyDirectory"),
                        localization.t("help.payload.destination")
                    ]
                )
                Spacer()
                Menu {
                    Button(localization.t("payload.fileOrFolder")) {
                        entries.append(PackagePayloadEntry(kind: .fileOrFolder))
                    }
                    Button(localization.t("payload.folderContents")) {
                        entries.append(PackagePayloadEntry(kind: .folderContents, destinationPath: "/"))
                    }
                    Button(localization.t("payload.emptyDirectory")) {
                        entries.append(PackagePayloadEntry(kind: .emptyDirectory, destinationPath: "/Library/Application Support"))
                    }
                } label: {
                    Label(localization.t("payload.add"), systemImage: "plus")
                }
                .help(localization.t("payload.add.help"))
            }

            if entries.isEmpty {
                Text(localization.t("payload.empty"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries.indices, id: \.self) { index in
                        PayloadEntryRow(entry: $entries[index]) {
                            entries.remove(at: index)
                        }
                    }
                }
            }
        }
    }
}

private struct SectionHelpHeader: View {
    @EnvironmentObject private var localization: AppLocalization
    let title: String
    let lines: [String]
    @State private var showsHelp = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)

            Button {
                showsHelp.toggle()
            } label: {
                Label("\(title) Help", systemImage: "questionmark.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help(localization.t("help.about", title))
            .popover(isPresented: $showsHelp, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)

                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 340, alignment: .leading)
                .padding(14)
            }
        }
    }
}

private struct MacOSVersionPicker: View {
    @EnvironmentObject private var localization: AppLocalization
    @Binding var selection: String

    var body: some View {
        Picker(localization.t("picker.minimumMacOS"), selection: $selection) {
            Text(localization.t("macos.noMinimum")).tag("")

            if shouldShowCustomSelection {
                Divider()
                Text(localization.t("macos.custom", selection)).tag(selection)
            }

            Divider()

            ForEach(MacOSRelease.all) { release in
                Text(release.title).tag(release.version)
            }
        }
        .labelsHidden()
        .help(localization.t("macos.help"))
    }

    private var shouldShowCustomSelection: Bool {
        !selection.isEmpty && !MacOSRelease.all.contains { $0.version == selection }
    }
}

private struct MacOSRelease: Identifiable {
    let version: String
    let name: String
    let prefix: String

    var id: String { version }
    var title: String { "\(prefix) \(version) \(name)" }

    static let all: [MacOSRelease] = [
        MacOSRelease(version: "26.0", name: "Tahoe", prefix: "macOS"),
        MacOSRelease(version: "15.0", name: "Sequoia", prefix: "macOS"),
        MacOSRelease(version: "14.0", name: "Sonoma", prefix: "macOS"),
        MacOSRelease(version: "13.0", name: "Ventura", prefix: "macOS"),
        MacOSRelease(version: "12.0", name: "Monterey", prefix: "macOS"),
        MacOSRelease(version: "11.0", name: "Big Sur", prefix: "macOS"),
        MacOSRelease(version: "10.15", name: "Catalina", prefix: "macOS"),
        MacOSRelease(version: "10.14", name: "Mojave", prefix: "macOS"),
        MacOSRelease(version: "10.13", name: "High Sierra", prefix: "macOS"),
        MacOSRelease(version: "10.12", name: "Sierra", prefix: "macOS"),
        MacOSRelease(version: "10.11", name: "El Capitan", prefix: "OS X"),
        MacOSRelease(version: "10.10", name: "Yosemite", prefix: "OS X"),
        MacOSRelease(version: "10.9", name: "Mavericks", prefix: "OS X"),
        MacOSRelease(version: "10.8", name: "Mountain Lion", prefix: "OS X"),
        MacOSRelease(version: "10.7", name: "Lion", prefix: "Mac OS X"),
        MacOSRelease(version: "10.6", name: "Snow Leopard", prefix: "Mac OS X"),
        MacOSRelease(version: "10.5", name: "Leopard", prefix: "Mac OS X"),
        MacOSRelease(version: "10.4", name: "Tiger", prefix: "Mac OS X"),
        MacOSRelease(version: "10.3", name: "Panther", prefix: "Mac OS X"),
        MacOSRelease(version: "10.2", name: "Jaguar", prefix: "Mac OS X"),
        MacOSRelease(version: "10.1", name: "Puma", prefix: "Mac OS X"),
        MacOSRelease(version: "10.0", name: "Cheetah", prefix: "Mac OS X")
    ]
}

private struct PayloadEntryRow: View {
    @EnvironmentObject private var localization: AppLocalization
    @Binding var entry: PackagePayloadEntry
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(localization.t("picker.payloadKind"), selection: $entry.kind) {
                    ForEach(PackagePayloadKind.allCases) { kind in
                        Text(kind.localizedTitle(localization)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                TextField(localization.t("field.destination"), text: $entry.destinationPath)

                Button(role: .destructive) {
                    remove()
                } label: {
                    Label(localization.t("button.remove"), systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .help(localization.t("payload.remove.help"))
            }

            if entry.kind != .emptyDirectory {
                PathField(
                    path: $entry.sourcePath,
                    mode: entry.kind == .folderContents ? .directory : .fileOrDirectory,
                    optional: false
                )
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct InstallerPageResourceEditor: View {
    @EnvironmentObject private var localization: AppLocalization
    let title: String
    @Binding var defaultPath: String
    @Binding var localizations: [LocalizedInstallerResource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text(title)
                    PathField(path: $defaultPath, mode: .file, optional: true)
                }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(localizations.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            InstallerLanguagePicker(languageCode: $localizations[index].languageCode)
                                .frame(width: 190)
                            PathField(path: $localizations[index].path, mode: .file, optional: false)
                            Button {
                                localizations.remove(at: index)
                            } label: {
                                Label(localization.t("button.remove"), systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .help(localization.t("localization.remove.help"))
                        }
                    }

                    HStack {
                        Button {
                            localizations.append(LocalizedInstallerResource(languageCode: nextLanguageCode))
                        } label: {
                            Label(localization.t("localization.add"), systemImage: "plus")
                        }
                        .help(localization.t("localization.add.help"))
                        Spacer()
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(localization.t("localization.title"))
                    .font(.subheadline)
            }
        }
    }

    private var nextLanguageCode: String {
        let usedCodes = Set(localizations.map { InstallerLanguageOption.normalizedCode($0.languageCode) })
        return InstallerLanguageOption.popular.first { !usedCodes.contains($0.code) }?.code ?? "en"
    }
}

private struct InstallerLanguagePicker: View {
    @EnvironmentObject private var localization: AppLocalization
    @Binding var languageCode: String

    var body: some View {
        Picker(localization.t("picker.language"), selection: $languageCode) {
            ForEach(InstallerLanguageOption.popular) { option in
                Text(option.title(localization))
                    .tag(option.code)
            }

            if let customOption = InstallerLanguageOption.customOption(for: languageCode) {
                Divider()
                Text(customOption.title(localization))
                    .tag(customOption.code)
            }
        }
        .labelsHidden()
        .help(localization.t("localization.language.help"))
    }
}

private struct InstallerLanguageOption: Identifiable, Equatable {
    let code: String
    let flag: String
    let name: String

    var id: String { code }
    @MainActor
    func title(_ localization: AppLocalization) -> String {
        let localizedName = name == "Custom"
            ? localization.t("installerLanguage.custom")
            : localization.t("installerLanguage.\(code)", fallback: name)
        return "\(flag) \(localizedName) (\(code))"
    }

    static let popular: [InstallerLanguageOption] = [
        InstallerLanguageOption(code: "en", flag: "🇺🇸", name: "English"),
        InstallerLanguageOption(code: "uk", flag: "🇺🇦", name: "Ukrainian"),
        InstallerLanguageOption(code: "es", flag: "🇪🇸", name: "Spanish"),
        InstallerLanguageOption(code: "fr", flag: "🇫🇷", name: "French"),
        InstallerLanguageOption(code: "de", flag: "🇩🇪", name: "German"),
        InstallerLanguageOption(code: "it", flag: "🇮🇹", name: "Italian"),
        InstallerLanguageOption(code: "pt_BR", flag: "🇧🇷", name: "Portuguese"),
        InstallerLanguageOption(code: "pl", flag: "🇵🇱", name: "Polish"),
        InstallerLanguageOption(code: "ru", flag: "🇷🇺", name: "Russian"),
        InstallerLanguageOption(code: "zh_CN", flag: "🇨🇳", name: "Chinese Simplified"),
        InstallerLanguageOption(code: "zh_TW", flag: "🇹🇼", name: "Chinese Traditional"),
        InstallerLanguageOption(code: "ja", flag: "🇯🇵", name: "Japanese"),
        InstallerLanguageOption(code: "ko", flag: "🇰🇷", name: "Korean"),
        InstallerLanguageOption(code: "nl", flag: "🇳🇱", name: "Dutch"),
        InstallerLanguageOption(code: "tr", flag: "🇹🇷", name: "Turkish")
    ]

    static func customOption(for code: String) -> InstallerLanguageOption? {
        let normalized = normalizedCode(code)
        guard !normalized.isEmpty,
              !popular.contains(where: { $0.code == normalized }) else {
            return nil
        }
        return InstallerLanguageOption(code: code, flag: "🌐", name: "Custom")
    }

    static func normalizedCode(_ code: String) -> String {
        var normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(".lproj") {
            normalized.removeLast(".lproj".count)
        }
        return normalized
    }
}

private struct PathField: View {
    @EnvironmentObject private var localization: AppLocalization
    enum Mode {
        case file
        case directory
        case fileOrDirectory
    }

    @Binding var path: String
    let mode: Mode
    var optional: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            TextField(optional ? localization.t("path.optional") : localization.t("path.choosePath"), text: $path)

            Button {
                choosePath()
            } label: {
                Label(localization.t("path.choose"), systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .help(optional ? localization.t("path.chooseOptional.help") : localization.t("path.choose.help"))
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = mode == .file || mode == .fileOrDirectory
        panel.canChooseDirectories = mode == .directory || mode == .fileOrDirectory
        panel.title = localization.t("path.choosePath")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }
}

private enum SigningIdentityProvider {
    static func load() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-identity", "-v"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        let pattern = #""([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, range: range)
        let identities = matches.compactMap { match -> String? in
            guard let matchRange = Range(match.range(at: 1), in: output) else { return nil }
            let identity = String(output[matchRange])
            return identity.localizedCaseInsensitiveContains("Installer") ? identity : nil
        }

        return Array(Set(identities)).sorted()
    }
}
