//
//  DevNexusApp.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI

@main
struct DevNexusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 注入全局自启设置
    @State private var launchSettings = LaunchSettings.shared
    @State private var commandConfigService: CommandConfigService
    @State private var projectService: ProjectService
    @State private var mainWindowNavigationCoordinator = MainWindowNavigationCoordinator.shared

    init() {
        let commandConfigService = CommandConfigService()
        _commandConfigService = State(wrappedValue: commandConfigService)
        _projectService = State(wrappedValue: ProjectService(commandConfigService: commandConfigService))
    }

    var body: some Scene {
        // 主窗口
        Window("DevNexus", id: "main") {
            ContentView(
                commandConfigService: commandConfigService,
                projectService: projectService
            )
            .environment(mainWindowNavigationCoordinator)
            .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            MainWindowNavigationCommands()
            DevNexusAppCommands()
        }

        // 原生设置场景 (Cmd + ,)
        Settings {
            SettingsView(
                projectService: projectService,
                commandConfigService: commandConfigService
            )
                .environment(launchSettings)
        }

        Window("操作日志", id: "logs") {
            LogView()
                .environment(LogService.shared)
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1040, height: 720)

        Window("关于 DevNexus", id: "about") {
            AboutView()
                .frame(minWidth: 520, minHeight: 420)
        }
        .defaultSize(width: 560, height: 460)
        .windowResizability(.contentSize)

        // 菜单栏
        MenuBarExtra("DevNexus", systemImage: "macbook.and.iphone") {
            MenuBarView()
                .environment(launchSettings)
                .environment(mainWindowNavigationCoordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// 设置视图
struct SettingsView: View {
    let projectService: ProjectService
    let commandConfigService: CommandConfigService
    
    var body: some View {
        SettingsContentView(
            projectService: projectService,
            commandConfigService: commandConfigService
        )
        .frame(width: 560, height: 320)
        .navigationTitle("设置")
    }
}

struct DevNexusAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 DevNexus") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .windowArrangement) {
            Divider()

            Button("操作日志") {
                openWindow(id: "logs")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

struct MainWindowNavigationCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = MainWindowNavigationCoordinator.shared.registerOpenMainWindowAction {
            openWindow(id: "main")
        }

        CommandGroup(before: .appInfo) { }
    }
}
