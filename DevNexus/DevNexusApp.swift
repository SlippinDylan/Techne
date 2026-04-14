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

    var body: some Scene {
        // 主窗口
        WindowGroup(id: "main") {
            ContentView()
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
            SettingsView()
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
    @Environment(LaunchSettings.self) private var launchSettings
    
    var body: some View {
        Form {
            Section("系统设置") {
                @Bindable var settings = launchSettings
                Toggle("登录时隐式启动", isOn: $settings.isLaunchAtLoginEnabled)
                    .help("开启后，应用将在系统启动时自动运行，且不会弹出主窗口")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 150)
        .navigationTitle("设置")
    }
}
