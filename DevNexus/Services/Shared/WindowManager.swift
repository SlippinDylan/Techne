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
        MainWindowCoordinator(
            identifier: identifier,
            openWindow: { }
        ).showMainWindow()
    }
}
