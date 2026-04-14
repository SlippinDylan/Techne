//
//  ContentView.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .devEnvironment
    @State private var chromeDetectionService = ChromeDetectionService()
    @State private var devServerDetectionService = DevServerDetectionService()
    @State private var commandConfigService: CommandConfigService
    @State private var projectService: ProjectService
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

    init() {
        let commandConfig = CommandConfigService()
        _commandConfigService = State(wrappedValue: commandConfig)
        _projectService = State(wrappedValue: ProjectService(commandConfigService: commandConfig))
    }

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
                    MainSettingsView()
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
    @Environment(LaunchSettings.self) private var launchSettings
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("偏好设置")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.bottom, 8)
                
                GroupBox(label: Label("基础设置", systemImage: "cpu")) {
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
                
                Text("应用状态数据存放在 ~/Library/Application Support/studio.slippindylan.DevNexus/ 目录下。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(32)
            .frame(maxWidth: 800)
        }
    }
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
    ContentView()
}
