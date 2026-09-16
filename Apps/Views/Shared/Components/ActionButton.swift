//
//  ActionButton.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 操作按钮组件
/// 用于卡片中的操作按钮，支持禁用和危险状态
struct ActionButton: View {
    let icon: String
    let action: () -> Void
    let tooltip: String
    var isDisabled: Bool = false
    var isDestructive: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(buttonColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                        .fill(isHovered && !isDisabled ? Color.blue.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                        .stroke(isHovered && !isDisabled ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var buttonColor: Color {
        guard !isDisabled else { return .secondary.opacity(0.5) }
        let activeColor: Color = isDestructive ? .red : .blue
        return isHovered ? activeColor : .secondary
    }
}

#Preview {
    HStack(spacing: 12) {
        ActionButton(
            icon: "arrow.clockwise",
            action: {},
            tooltip: "刷新"
        )

        ActionButton(
            icon: "play.fill",
            action: {},
            tooltip: "启动"
        )

        ActionButton(
            icon: "trash",
            action: {},
            tooltip: "删除",
            isDestructive: true
        )

        ActionButton(
            icon: "stop.fill",
            action: {},
            tooltip: "停止",
            isDisabled: true
        )
    }
    .padding()
}
