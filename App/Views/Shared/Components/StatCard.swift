//
//  StatCard.swift
//  Techne
//
//  统计卡片组件
//  用于显示单个统计项，独立卡片样式
//

import SwiftUI

/// 统计卡片组件
/// 用于显示单个统计信息，独立卡片样式
struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .blue
    var isClickable: Bool = false
    var action: (() -> Void)?

    var body: some View {
        AppPanelCard {
            StatCardContent(icon: icon, label: label, value: value, iconColor: iconColor)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}

/// 统计卡片行容器
/// 用于水平排列多个统计卡片，自动等分宽度
struct StatCardsRow: View {
    let cards: [StatCardData]
    var joinsCards = false

    var body: some View {
        if joinsCards {
            HStack(spacing: 0) {
                ForEach(cards.indices, id: \.self) { index in
                    if index > cards.startIndex {
                        Divider()
                            .frame(height: 48)
                    }

                    let card = cards[index]
                    StatCardContent(
                        icon: card.icon,
                        label: card.label,
                        value: card.value,
                        iconColor: card.iconColor
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        card.action?()
                    }
                }
            }
            .background(.blue.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius)
                    .stroke(.blue.opacity(0.1), lineWidth: 1)
            }
        } else {
            HStack(spacing: AppConfig.UI.largeSpacing) {
                ForEach(cards) { card in
                    StatCard(
                        icon: card.icon,
                        label: card.label,
                        value: card.value,
                        iconColor: card.iconColor,
                        isClickable: card.isClickable,
                        action: card.action
                    )
                }
            }
        }
    }
}

private struct StatCardContent: View {
    let icon: String
    let label: String
    let value: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Image(systemName: icon)
                .font(.system(size: AppConfig.UI.iconSize))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
                Text(label)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: AppConfig.UI.mediumFontSize + 1, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(AppConfig.UI.largePadding)
        .frame(maxWidth: .infinity)
    }
}

/// 统计卡片数据模型
struct StatCardData: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .blue
    var isClickable: Bool = false
    var action: (() -> Void)?
}

#Preview {
    VStack {
        StatCardsRow(cards: [
            StatCardData(icon: "folder.badge.plus", label: "已添加的项目", value: "5"),
            StatCardData(icon: "play.circle.fill", label: "运行中的项目", value: "3"),
            StatCardData(icon: "doc.badge.ellipsis", label: "工作区未提交文件", value: "12"),
            StatCardData(icon: "globe", label: "运行中的实例", value: "8", isClickable: true, action: {})
        ])
    }
    .padding()
}
