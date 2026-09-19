//
//  ContentView.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let commandConfigService: CommandConfigService
    let projectService: ProjectService
    let updateController: ApplicationUpdateController
    @Environment(MainWindowNavigationCoordinator.self) private var mainWindowNavigation

    @State private var selectedItem: SidebarItem? = .devEnvironment
    @State private var chromeDetectionService = ChromeDetectionService()
    @State private var devServerDetectionService = DevServerDetectionService()
    @State private var browserDetectionService = BrowserDetectionService()
    @State private var adbDeployViewModel = ADBDeployViewModel()
    @State private var launchSettings = LaunchSettings.shared
    @State private var showingManualBrowserLaunch = false

    // LogService 是单例，直接引用
    private var logService: LogService { LogService.shared }

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(SidebarItem.primaryItems, selection: $selectedItem) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
                    .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listStyle(.sidebar)
            .safeAreaBar(edge: .bottom, alignment: .leading, spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(SidebarItem.utilityItems) { item in
                        utilitySidebarRow(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            // 详情区域
            Group {
                switch selectedItem ?? .devEnvironment {
                case .devEnvironment:
                    ProjectListView(projectType: .devServer)
                        .environment(devServerDetectionService)
                        .environment(chromeDetectionService)
                        .environment(browserDetectionService)
                        .environment(projectService)
                        .environment(logService)
                case .miniApp:
                    ProjectListView(projectType: .miniApp)
                        .environment(projectService)
                        .environment(devServerDetectionService)
                        .environment(chromeDetectionService)
                        .environment(browserDetectionService)
                        .environment(logService)
                case .adbDeploy:
                    ADBDeployView(viewModel: adbDeployViewModel)
                case .settings:
                    SettingsContentView(
                        projectService: projectService,
                        commandConfigService: commandConfigService,
                        updateController: updateController
                    )
                case .logs:
                    LogView()
                        .environment(logService)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle(navigationSubtitle)
            .sheet(isPresented: $showingManualBrowserLaunch) {
                ManualBrowserLaunchSheet(browsers: browserDetectionService.installedBrowsers) { request in
                    let result = await BrowserLaunchService().launchBrowser(request)
                    switch result {
                    case .success:
                        return .success(())
                    case .failure(let error):
                        return .failure(error)
                    }
                }
            }
            .toolbar {
                let item = selectedItem ?? .devEnvironment
                if item == .devEnvironment || item == .miniApp {
                    ToolbarItem(placement: .primaryAction) {
                        if projectService.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 28, height: 28)
                        } else {
                            Button(action: { refreshCurrentSidebarItem(item) }) {
                                Label("刷新状态", systemImage: "arrow.clockwise")
                                    .labelStyle(.iconOnly)
                            }
                            .help("刷新状态 (Cmd+R)")
                            .keyboardShortcut("r", modifiers: .command)
                        }
                    }

                    if item == .devEnvironment {
                        ToolbarSpacer(.fixed, placement: .primaryAction)

                        ToolbarItem(placement: .primaryAction) {
                            Button(action: presentManualBrowserLaunch) {
                                Label("新建浏览器实例", systemImage: "globe.badge.chevron.backward")
                                    .labelStyle(.iconOnly)
                            }
                            .help("新建浏览器实例")
                        }
                    }

                    ToolbarSpacer(.fixed, placement: .primaryAction)

                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            if item == .devEnvironment {
                                NotificationCenter.default.post(name: .addDevProject, object: nil)
                            } else if item == .miniApp {
                                NotificationCenter.default.post(name: .addMiniAppProject, object: nil)
                            }
                        }) {
                            Label(
                                AppLocalized(item == .devEnvironment ? "添加服务" : "添加项目"),
                                systemImage: "plus"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .help(AppLocalized(item == .devEnvironment ? "添加服务" : "添加项目"))
                    }
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 1080, minHeight: 720)
        .onChange(of: selectedItem) { oldValue, newValue in
            if newValue == nil {
                selectedItem = oldValue ?? .devEnvironment
            }
        }
        .onAppear {
            applyPendingSidebarSelection()
        }
        .onChange(of: mainWindowNavigation.selectionRevision) { _, _ in
            applyPendingSidebarSelection()
        }
    }

    // MARK: - Helper Views & Methods

    private func utilitySidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selectedItem == item

        return Button {
            selectedItem = item
        } label: {
            Label(item.title, systemImage: item.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func applyPendingSidebarSelection() {
        guard let item = mainWindowNavigation.consumePendingSidebarItem() else {
            return
        }
        selectedItem = item
    }

    private func refreshCurrentSidebarItem(_ item: SidebarItem) {
        projectService.refreshAll()

        if item == .devEnvironment {
            devServerDetectionService.refresh()
            chromeDetectionService.refresh()
            browserDetectionService.refresh()
        }
    }

    private func presentManualBrowserLaunch() {
        browserDetectionService.refresh()
        showingManualBrowserLaunch = true
    }

    private var navigationTitle: String {
        (selectedItem ?? .devEnvironment).title
    }

    private var navigationSubtitle: String {
        (selectedItem ?? .devEnvironment).subtitle
    }
}

extension ContentView {
    @MainActor
    static func preview() -> some View {
        ContentViewPreviewEnvironment.make().makeView()
    }
}

struct ContentViewPreviewEnvironment {
    private let previewPersistenceSession: PreviewPersistenceSession
    let commandConfigService: CommandConfigService
    let projectService: ProjectService
    let navigationCoordinator: MainWindowNavigationCoordinator

    var persistenceRoot: PersistenceRoot {
        previewPersistenceSession.persistenceRoot
    }

    @MainActor
    static func make(
        fileManager: FileManager = .default,
        navigationCoordinator: MainWindowNavigationCoordinator = MainWindowNavigationCoordinator()
    ) -> ContentViewPreviewEnvironment {
        let previewPersistenceSession = PreviewPersistenceSession(fileManager: fileManager)
        let persistenceRoot = previewPersistenceSession.persistenceRoot
        let commandConfigService = CommandConfigService(
            persistenceService: PersistenceService<CommandConfig>(
                filename: "commandconfigs.json",
                root: persistenceRoot
            )
        )
        let projectService = ProjectService(
            commandConfigService: commandConfigService,
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                root: persistenceRoot
            ),
            startupBehavior: .empty
        )

        return ContentViewPreviewEnvironment(
            previewPersistenceSession: previewPersistenceSession,
            commandConfigService: commandConfigService,
            projectService: projectService,
            navigationCoordinator: navigationCoordinator
        )
    }

    @MainActor
    func makeView() -> some View {
        ContentView(
            commandConfigService: commandConfigService,
            projectService: projectService,
            updateController: ApplicationUpdateController(updaterEnabled: false)
        )
        .environment(LaunchSettings.shared)
        .environment(navigationCoordinator)
    }
}

enum SettingsPane: String, CaseIterable {
    case general
    case about

    var title: String {
        switch self {
        case .general: AppLocalized("通用")
        case .about: AppLocalized("关于")
        }
    }
}

struct SettingsContentView: View {
    @Environment(LaunchSettings.self) private var launchSettings
    @Environment(MainWindowNavigationCoordinator.self) private var mainWindowNavigation
    let projectService: ProjectService
    let commandConfigService: CommandConfigService
    let updateController: ApplicationUpdateController

    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupDocument = BackupService.makeDocument(projects: [], commandConfigs: [])
    @State private var backupAlert: BackupAlertContext?
    @State private var selectedApplicationLanguage = ApplicationLanguage.selected()
    @State private var showingLanguageRelaunchConfirmation = false
    @State private var selectedPane: SettingsPane = .general
    @Namespace private var paneSelectorNamespace

    var body: some View {
        selectedPaneContent
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    paneSelector
                }
                .sharedBackgroundVisibility(.hidden)
            }
        .fileExporter(
            isPresented: $exportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: BackupService.defaultFilename
        ) { result in
            if case .failure(let error) = result {
                backupAlert = .init(title: AppLocalized("备份导出失败"), message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $importingBackup,
            allowedContentTypes: TechneBackupDocument.readableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                do {
                    try BackupService.mergeImport(
                        from: url,
                        projectService: projectService,
                        commandConfigService: commandConfigService
                    )
                } catch {
                    backupAlert = .init(title: AppLocalized("备份导入失败"), message: error.localizedDescription)
                }
            case .failure(let error):
                backupAlert = .init(title: AppLocalized("备份导入失败"), message: error.localizedDescription)
            }
        }
        .alert(item: $backupAlert) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .alert("语言更改将在重新启动后生效", isPresented: $showingLanguageRelaunchConfirmation) {
            Button("稍后", role: .cancel) {}
            Button("重新启动") {
                ApplicationRelaunchController.shared.requestRelaunch()
            }
        } message: {
            Text("Techne 将在重新启动后使用所选语言。")
        }
        .onAppear {
            selectedPane = mainWindowNavigation.consumePendingSettingsPane() ?? .general
        }
        .onChange(of: mainWindowNavigation.selectionRevision) { _, _ in
            applyPendingSettingsPane()
        }
        .onChange(of: selectedApplicationLanguage) { _, language in
            showingLanguageRelaunchConfirmation = ApplicationLanguage.select(language)
        }
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selectedPane {
        case .general:
            generalSettingsPane
        case .about:
            AboutView(updateController: updateController)
        }
    }

    private var generalSettingsPane: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSectionHeader("通用", systemImage: "cpu")

                    GroupBox {
                        HStack {
                            Label("开机自动启动", systemImage: "power.circle")
                                .font(.headline)
                            Spacer()
                            @Bindable var settings = launchSettings
                            Toggle("", isOn: $settings.isLaunchAtLoginEnabled)
                                .toggleStyle(.switch)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()
                            .padding(.horizontal, 16)

                        HStack {
                            Label("应用语言", systemImage: "globe")
                                .font(.headline)
                            Spacer()
                            Picker("应用语言", selection: $selectedApplicationLanguage) {
                                ForEach(ApplicationLanguage.allCases, id: \.self) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    settingsSectionHeader("数据与备份", systemImage: "externaldrive")

                    GroupBox {
                        HStack(alignment: .center, spacing: 16) {
                            Text("导出当前项目与命令配置，或从备份文件恢复本地数据。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 10) {
                                CleanMyMacButton(
                                    title: AppLocalized("导出备份"),
                                    icon: nil,
                                    action: {
                                        backupDocument = BackupService.makeDocument(
                                            projects: projectService.projects,
                                            commandConfigs: commandConfigService.configs
                                        )
                                        exportingBackup = true
                                    },
                                    style: .secondary,
                                    isDestructive: false
                                )

                                CleanMyMacButton(
                                    title: AppLocalized("导入备份"),
                                    icon: nil,
                                    action: {
                                        importingBackup = true
                                    },
                                    style: .secondary,
                                    isDestructive: false
                                )

                                CleanMyMacButton(
                                    title: AppLocalized("打开数据目录"),
                                    icon: nil,
                                    action: {
                                        BackupService.revealAppSupportDirectory()
                                    },
                                    style: .secondary,
                                    isDestructive: false
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                
                Text("应用状态数据存放在 ~/Library/Application Support/studio.slippindylan.Techne/ 目录下。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(AppConfig.UI.extraLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paneSelector: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SettingsPane.allCases, id: \.self) { pane in
                    paneButton(for: pane)
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .frame(maxWidth: 200)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func paneButton(for pane: SettingsPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                selectedPane = pane
            }
        } label: {
            Text(pane.title)
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, AppConfig.UI.smallPadding)
                .frame(minWidth: 80, minHeight: 32)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
                    .glassEffectID("settings-pane-selection", in: paneSelectorNamespace)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func applyPendingSettingsPane() {
        guard let pane = mainWindowNavigation.consumePendingSettingsPane() else {
            return
        }
        selectedPane = pane
    }

    private func settingsSectionHeader(_ title: String, systemImage: String) -> some View {
        Label(AppLocalized(title), systemImage: systemImage)
            .font(.headline)
    }

}

private struct BackupAlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Sidebar Item Enum

enum SidebarItem: String, CaseIterable, Identifiable {
    case devEnvironment = "开发服务与实例"
    case miniApp = "微信小程序构建"
    case adbDeploy = "安卓应用部署"
    case settings = "设置"
    case logs = "日志"

    static let primaryItems: [SidebarItem] = [.devEnvironment, .miniApp, .adbDeploy]
    static let utilityItems: [SidebarItem] = [.settings, .logs]

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .devEnvironment: return "pc"
        case .miniApp: return "app.badge"
        case .adbDeploy: return "iphone.gen3"
        case .settings: return "gearshape"
        case .logs: return "doc.text"
        }
    }

    var title: String { AppLocalized(rawValue) }

    var subtitle: String {
        switch self {
        case .devEnvironment: return AppLocalized("统一管理开发服务和关联的浏览器实例")
        case .miniApp: return AppLocalized("管理微信小程序项目，快速切换分支并构建")
        case .adbDeploy: return AppLocalized("通过 ADB 快速部署 APK 到 Android 设备")
        case .settings: return AppLocalized("管理启动选项、数据与备份")
        case .logs: return AppLocalized("查看和筛选应用操作日志")
        }
    }
}

#Preview {
    ContentView.preview()
}
