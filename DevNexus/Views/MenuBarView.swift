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

            Button("设置") {
                openAndFocusWindow()
                NotificationCenter.default.post(name: .switchToSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("日志") {
                openAndFocusWindow()
                NotificationCenter.default.post(name: .switchToLog, object: nil)
            }
            .keyboardShortcut("6", modifiers: .command)

            Divider()

            Button("关于") {
                openAndFocusWindow()
                NotificationCenter.default.post(name: .switchToAbout, object: nil)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Private Methods

    /// 唤起并聚焦窗口 (macOS 15 适配方案)
    private func openAndFocusWindow() {
        // 1. SwiftUI 唤起/聚焦窗口结构
        openWindow(id: "main")
        
        // 2. WindowManager 执行物理层面的“空间拉取”与“层级提权”
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            WindowManager.showMainWindow(identifier: "main")
        }
    }
}

#Preview {
    MenuBarView()
}
