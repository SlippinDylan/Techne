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
    enum Presentation {
        case standalone
        case grouped
    }

    let icon: String
    let action: () -> Void
    let tooltip: String
    var isDisabled: Bool = false
    var isDestructive: Bool = false
    var presentation: Presentation = .standalone

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: presentation == .grouped ? 12 : 14))
                .foregroundStyle(buttonColor)
                .frame(width: 28, height: 28)
                .background {
                    if presentation == .grouped {
                        Circle()
                            .fill(hoverBackgroundColor)
                    } else {
                        RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                            .fill(hoverBackgroundColor)
                    }
                }
                .overlay {
                    if presentation == .standalone {
                        RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                            .stroke(hoverBorderColor, lineWidth: 1)
                    }
                }
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

    private var hoverBackgroundColor: Color {
        guard isHovered && !isDisabled else { return .clear }
        return (isDestructive ? Color.red : Color.blue).opacity(0.1)
    }

    private var hoverBorderColor: Color {
        guard presentation == .standalone, isHovered && !isDisabled else { return .clear }
        return isDestructive ? .red : .blue
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
