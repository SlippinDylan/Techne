//
//  ClickableBranchLabel.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 可点击的分支标签
/// 点击后触发分支切换操作
struct ClickableBranchLabel: View {
    let branchName: String
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppConfig.UI.smallSpacing) {
                Image(systemName: "arrow.branch")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                Text(branchName)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppConfig.UI.smallFontSize - 2, weight: .semibold))
            }
            .padding(.horizontal, AppConfig.UI.smallPadding)
            .padding(.vertical, 3)
            .background(
                Color.secondary.opacity(isHovered ? 0.14 : 0.08),
                in: Capsule()
            )
            .foregroundStyle(isHovered ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
