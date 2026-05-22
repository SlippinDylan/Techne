//
//  MenuBarView.swift
//  DevNexus
//
//  菜单栏视图 - 使用 SwiftUI MenuBarExtra 实现
//

import SwiftUI
import ServiceManagement

/// 菜单栏视图 (终极适配对齐版)
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(MainWindowNavigationCoordinator.self) private var mainWindowNavigation

    var body: some View {
        Group {
            // 核心业务模块
            Button("开发服务与实例") {
                mainWindowNavigation.showMainWindow(selecting: .devEnvironment)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("微信小程序构建") {
                mainWindowNavigation.showMainWindow(selecting: .miniApp)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("安卓应用部署") {
                mainWindowNavigation.showMainWindow(selecting: .adbDeploy)
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            SettingsLink {
                Text("设置…")
            }

            Button("日志") {
                openWindow(id: "logs")
            }

            Divider()

            Button("关于 DevNexus") {
                openWindow(id: "about")
            }

            Button("退出 DevNexus") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

#Preview {
    MenuBarView()
}
