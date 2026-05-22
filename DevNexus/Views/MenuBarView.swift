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

    var body: some View {
        Group {
            // 核心业务模块
            Button("开发服务与实例") {
                openAndFocusWindow()
                NotificationCenter.default.post(name: .switchToDevEnvironment, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("微信小程序构建") {
                openAndFocusWindow()
                NotificationCenter.default.post(name: .switchToMiniApp, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("安卓应用部署") {
                openAndFocusWindow()
                NotificationCenter.default.post(name: .switchToADBDeploy, object: nil)
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

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Private Methods

    private func openAndFocusWindow() {
        MainWindowCoordinator(openWindow: { openWindow(id: "main") }).showMainWindow()
    }
}

#Preview {
    MenuBarView()
}
