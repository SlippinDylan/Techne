//
//  CardBackgroundColor.swift
//  DevNexus
//
//  自适应卡片背景色
//  在浅色模式下略带灰度，深色模式下使用系统控件背景色
//

import SwiftUI
import AppKit

extension Color {
    /// 卡片背景色
    /// - 深色模式：使用系统 controlBackgroundColor
    /// - 浅色模式：使用略带灰度的白色，与纯白背景形成微妙对比
    static var cardBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                // 深色模式：使用系统控件背景色
                return .controlBackgroundColor
            } else {
                // 浅色模式：使用略带灰度的白色 (RGB: 250, 250, 250)
                return NSColor(white: 0.98, alpha: 1.0)
            }
        })
    }

}
