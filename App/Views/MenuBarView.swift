//
//  MenuBarView.swift
//  Techne
//
//  菜单栏视图 - 使用 SwiftUI MenuBarExtra 实现
//

import SwiftUI

/// 菜单栏视图 (终极适配对齐版)
struct MenuBarView: View {
    @Environment(MainWindowNavigationCoordinator.self) private var mainWindowNavigation

    var body: some View {
        Group {
            // 核心业务模块
            Button {
                mainWindowNavigation.showMainWindow(selecting: .devEnvironment)
            } label: {
                Label("开发服务与实例", systemImage: SidebarItem.devEnvironment.icon)
            }

            Button {
                mainWindowNavigation.showMainWindow(selecting: .miniApp)
            } label: {
                Label("微信小程序构建", systemImage: SidebarItem.miniApp.icon)
            }

            Button {
                mainWindowNavigation.showMainWindow(selecting: .adbDeploy)
            } label: {
                Label("安卓应用部署", systemImage: SidebarItem.adbDeploy.icon)
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出 Techne", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

#Preview {
    MenuBarView()
        .environment(MainWindowNavigationCoordinator())
}
