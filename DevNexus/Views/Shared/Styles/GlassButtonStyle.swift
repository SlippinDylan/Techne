//
//  GlassButtonStyle.swift
//  DevNexus
//
//  Liquid Glass 按钮样式扩展
//  注意：此文件已废弃，请使用 Adaptation/AdaptiveButtonStyle.swift 中的
//  adaptiveGlassButtonStyle() 和 adaptiveGlassProminentButtonStyle()
//

import SwiftUI

extension View {
    /// 应用 Liquid Glass 按钮样式
    /// - Note: 已废弃，请使用 adaptiveGlassButtonStyle()
    @available(*, deprecated, message: "请使用 adaptiveGlassButtonStyle()")
    @ViewBuilder
    func glassButtonStyleIfAvailable() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
