//
//  ContentView.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let commandConfigService: CommandConfigService
    let projectService: ProjectService

    @State private var selectedItem: SidebarItem? = .devEnvironment
    @State private var chromeDetectionService = ChromeDetectionService()
    @State private var devServerDetectionService = DevServerDetectionService()
    @State private var adbDeployViewModel = ADBDeployViewModel()
    @State private var launchSettings = LaunchSettings.shared

    // LogService 是单例，直接引用
    private var logService: LogService { LogService.shared }

    enum ContentType {
        case sidebarItem(SidebarItem)
        case commandConfig
        case settings
        case log
        case about
    }

    @State private var selectedContent: ContentType = .sidebarItem(.devEnvironment)

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            VStack(spacing: 0) {
                List(SidebarItem.allCases, selection: $selectedItem) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                        .padding(.vertical, 4)
                }
                .listStyle(.sidebar)

                Divider()

                // 底部按钮区域
                VStack(spacing: 0) {
                    bottomSidebarButton(title: "命令配置", icon: "terminal", type: .commandConfig)
                    bottomSidebarButton(title: "设置", icon: "gearshape", type: .settings)
                    bottomSidebarButton(title: "日志", icon: "doc.text", type: .log)
                    bottomSidebarButton(title: "关于", icon: "info.circle", type: .about)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            // 详情区域
            Group {
                switch selectedContent {
                case .sidebarItem(let item):
                    switch item {
                    case .devEnvironment:
                        ProjectListView(projectType: .devServer)
                            .environment(devServerDetectionService)
                            .environment(chromeDetectionService)
                            .environment(projectService)
                            .environment(commandConfigService)
                            .environment(logService)
                    case .miniApp:
                        ProjectListView(projectType: .miniApp)
                            .environment(projectService)
                            .environment(devServerDetectionService)
                            .environment(chromeDetectionService)
                            .environment(commandConfigService)
                            .environment(logService)
                    case .adbDeploy:
                        ADBDeployView(viewModel: adbDeployViewModel)
                    }
                case .commandConfig:
                    CommandConfigView()
                        .environment(commandConfigService)
                        .environment(logService)
                case .settings:
                    MainSettingsView(
                        projectService: projectService,
                        commandConfigService: commandConfigService
                    )
                        .environment(launchSettings)
                case .log:
                    LogView()
                        .environment(logService)
                case .about:
                    AboutView()
                }
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle(navigationSubtitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if case .sidebarItem(let item) = selectedContent {
                        if item == .devEnvironment || item == .miniApp {
                            HStack(spacing: 12) {
                                // Task 3: 恢复刷新按钮
                                if projectService.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Button(action: { refreshCurrentSidebarItem(item) }) {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .adaptiveGlassButtonStyle()
                                    .help("刷新状态 (Cmd+R)")
                                    .keyboardShortcut("r", modifiers: .command)
                                }

                                Button(action: {
                                    if item == .devEnvironment {
                                        NotificationCenter.default.post(name: .addDevProject, object: nil)
                                    } else if item == .miniApp {
                                        NotificationCenter.default.post(name: .addMiniAppProject, object: nil)
                                    }
                                }) {
                                    Image(systemName: "plus")
                                }
                                .adaptiveGlassButtonStyle()
                                .help(item == .devEnvironment ? "添加服务" : "添加项目")
                            }
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 1080, minHeight: 720)
        .onChange(of: selectedItem) { oldValue, newValue in
            if let newValue = newValue {
                selectedContent = .sidebarItem(newValue)
            }
        }
        // 通知监听：同步 UI 状态
        .onReceive(NotificationCenter.default.publisher(for: .switchToDevEnvironment)) { _ in switchTo(.devEnvironment) }
        .onReceive(NotificationCenter.default.publisher(for: .switchToMiniApp)) { _ in switchTo(.miniApp) }
        .onReceive(NotificationCenter.default.publisher(for: .switchToADBDeploy)) { _ in switchTo(.adbDeploy) }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSettings)) { _ in
            WindowManager.showMainWindow()
            selectedItem = nil
            selectedContent = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLog)) { _ in
            WindowManager.showMainWindow()
            selectedItem = nil
            selectedContent = .log
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToConfig)) { _ in
            WindowManager.showMainWindow()
            selectedItem = nil
            selectedContent = .commandConfig
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToAbout)) { _ in
            WindowManager.showMainWindow()
            selectedItem = nil
            selectedContent = .about
        }
    }

    // MARK: - Helper Views & Methods

    private func bottomSidebarButton(title: String, icon: String, type: ContentType) -> some View {
        Button(action: {
            selectedItem = nil
            selectedContent = type
        }) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func switchTo(_ item: SidebarItem) {
        WindowManager.showMainWindow()
        selectedItem = item
        selectedContent = .sidebarItem(item)
    }

    private func refreshCurrentSidebarItem(_ item: SidebarItem) {
        projectService.refreshAll()

        if item == .devEnvironment {
            devServerDetectionService.refresh()
            chromeDetectionService.refresh()
        }
    }

    private var navigationTitle: String {
        switch selectedContent {
        case .sidebarItem(let item): return item.title
        case .commandConfig: return "命令配置"
        case .settings: return "设置"
        case .log: return "操作日志"
        case .about: return "关于"
        }
    }

    private var navigationSubtitle: String {
        switch selectedContent {
        case .sidebarItem(let item): return item.subtitle
        case .commandConfig: return "管理项目的启动、编译、清理等命令配置"
        case .settings: return "管理应用的启动行为与全局偏好"
        case .log: return "查看应用中的所有操作记录"
        case .about: return "DevNexus 版本 1.0.0"
        }
    }
}

// MARK: - Main Settings View

struct MainSettingsView: View {
    let projectService: ProjectService
    let commandConfigService: CommandConfigService

    var body: some View {
        SettingsContentView(
            projectService: projectService,
            commandConfigService: commandConfigService
        )
    }
}

struct SettingsContentView: View {
    @Environment(LaunchSettings.self) private var launchSettings
    let projectService: ProjectService
    let commandConfigService: CommandConfigService

    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupDocument = DevNexusBackupDocument(
        payload: .init(schemaVersion: 1, exportedAt: .now, appVersion: "1.0.0", projects: [], commandConfigs: [])
    )
    @State private var backupAlert: BackupAlertContext?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSectionHeader("基础设置", systemImage: "cpu")

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
                                    title: "导出备份",
                                    icon: nil,
                                    action: {
                                        backupDocument = BackupService.makeDocument(
                                            projects: projectService.projects,
                                            commandConfigs: commandConfigService.configs
                                        )
                                        exportingBackup = true
                                    },
                                    style: .primary,
                                    isDestructive: false
                                )

                                CleanMyMacButton(
                                    title: "导入备份",
                                    icon: nil,
                                    action: {
                                        importingBackup = true
                                    },
                                    style: .primary,
                                    isDestructive: false
                                )

                                CleanMyMacButton(
                                    title: "打开数据目录",
                                    icon: nil,
                                    action: {
                                        BackupService.revealAppSupportDirectory()
                                    },
                                    style: .primary,
                                    isDestructive: false
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                
                Text("应用状态数据存放在 ~/Library/Application Support/studio.slippindylan.DevNexus/ 目录下。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(AppConfig.UI.extraLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileExporter(
            isPresented: $exportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: BackupService.defaultFilename
        ) { result in
            if case .failure(let error) = result {
                backupAlert = .init(title: "备份导出失败", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $importingBackup,
            allowedContentTypes: DevNexusBackupDocument.readableContentTypes,
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
                    backupAlert = .init(title: "备份导入失败", message: error.localizedDescription)
                }
            case .failure(let error):
                backupAlert = .init(title: "备份导入失败", message: error.localizedDescription)
            }
        }
        .alert(item: $backupAlert) { context in
            Alert(
                title: Text(context.title),
                message: Text(context.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    private func settingsSectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .devEnvironment: return "pc"
        case .miniApp: return "app.badge"
        case .adbDeploy: return "iphone.gen3"
        }
    }

    var title: String { return rawValue }

    var subtitle: String {
        switch self {
        case .devEnvironment: return "统一管理开发服务和关联的浏览器实例"
        case .miniApp: return "管理微信小程序项目，快速切换分支并构建"
        case .adbDeploy: return "通过 ADB 快速部署 APK 到 Android 设备"
        }
    }
}

#Preview {
    let commandConfigService = CommandConfigService()
    ContentView(
        commandConfigService: commandConfigService,
        projectService: ProjectService(commandConfigService: commandConfigService)
    )
}
