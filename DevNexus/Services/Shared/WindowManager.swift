//
//  WindowManager.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/03/10.
//

import AppKit
import SwiftUI

/// 窗口管理专家 (macOS 15 适配版)
/// 处理焦点抢占、跨桌面 (Spaces) 移动以及层级提权
@MainActor
final class WindowManager: Sendable {
    
    /// 强制激活并拉取主窗口到当前活跃桌面
    /// - Parameter identifier: 窗口标识符
    static func showMainWindow(identifier: String = "main") {
        // 1. 提权激活策略：确保应用在 Dock 栏可见并能拥有菜单栏
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        
        // 2. 现代激活调用
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        
        // 3. 窗口调度逻辑
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == identifier }) else {
            return
        }
        
        // 核心修复：collectionBehavior 配置
        // .moveToActiveSpace: 关键！将窗口从其他桌面拉取到当前用户正在看的桌面
        // .fullScreenAuxiliary: 允许在其他 App 全屏时浮动显示
        window.collectionBehavior = [.moveToActiveSpace, .managed, .fullScreenAuxiliary]
        
        // 提权并获得第一响应者身份
        window.makeKeyAndOrderFront(nil)
        
        // 破除层级遮挡，无视其他应用的遮盖
        window.orderFrontRegardless()
    }
}
