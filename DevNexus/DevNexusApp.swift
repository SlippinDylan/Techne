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

    init() {
        let commandConfigService = CommandConfigService()
        _commandConfigService = State(wrappedValue: commandConfigService)
        _projectService = State(wrappedValue: ProjectService(commandConfigService: commandConfigService))
    }

    var body: some Scene {
        // 主窗口
        WindowGroup(id: "main") {
            ContentView(
                commandConfigService: commandConfigService,
                projectService: projectService
            )
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            // 移除默认的 Cmd+Q 行为，由 AppDelegate 处理双击退出
            CommandGroup(replacing: .appTermination) { }
        }

        // 原生设置场景 (Cmd + ,)
        Settings {
            SettingsView(
                projectService: projectService,
                commandConfigService: commandConfigService
            )
                .environment(launchSettings)
        }

        // 菜单栏
        MenuBarExtra("DevNexus", systemImage: "macbook.and.iphone") {
            MenuBarView()
                .environment(launchSettings)
        }
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
