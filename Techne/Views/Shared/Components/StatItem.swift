//
//  StatItem.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 统计项组件
/// 用于显示统计信息，包含图标、标签和数值
struct StatItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Image(systemName: icon)
                .font(.system(size: AppConfig.UI.iconSize))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
                Text(label)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: AppConfig.UI.mediumFontSize + 1, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    StatItem(
        icon: "folder.badge.plus",
        label: "已添加的项目",
        value: "5"
    )
    .padding()
}
