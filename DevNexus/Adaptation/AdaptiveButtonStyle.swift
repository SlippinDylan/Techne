//
//  AdaptiveButtonStyle.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/01/19.
//

import SwiftUI

/// 自适应按钮样式扩展
///
/// 根据系统版本自动选择合适的按钮样式：
/// - macOS 26+：使用 Liquid Glass 设计语言
/// - macOS 15-25：使用经典 bordered 样式作为优雅降级
extension View {
    /// 自适应玻璃按钮样式
    ///
    /// - macOS 26+: `.buttonStyle(.glass)`
    /// - macOS 15-25: `.buttonStyle(.bordered)`
    @ViewBuilder
    func adaptiveGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 自适应强调玻璃按钮样式
    ///
    /// - macOS 26+: `.buttonStyle(.glassProminent)`
    /// - macOS 15-25: `.buttonStyle(.borderedProminent)`
    @ViewBuilder
    func adaptiveGlassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
