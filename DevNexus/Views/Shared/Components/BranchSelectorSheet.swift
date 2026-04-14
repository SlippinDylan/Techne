//
//  BranchSelectorSheet.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 分支选择弹窗
/// 用于选择并切换 Git 分支
struct BranchSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentBranch: String
    let branches: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text("切换分支")
                .font(.system(size: AppConfig.UI.titleFontSize, weight: .semibold))

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(AppConfig.UI.extraLargePadding)
    }

    // MARK: - Content View

    private var contentView: some View {
        Group {
            if branches.isEmpty {
                emptyStateView
            } else {
                branchListView
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: AppConfig.UI.largePadding) {
            Image(systemName: "arrow.branch")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("未检测到分支")
                .font(.system(size: AppConfig.UI.mediumFontSize))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Branch List View

    private var branchListView: some View {
        ScrollView {
            VStack(spacing: AppConfig.UI.mediumSpacing) {
                ForEach(branches, id: \.self) { branch in
                    BranchRow(
                        branch: branch,
                        isCurrentBranch: branch == currentBranch,
                        onSelect: {
                            if branch != currentBranch {
                                onSelect(branch)
                            }
                        }
                    )
                }
            }
            .padding(AppConfig.UI.extraLargePadding)
        }
    }
}

// MARK: - Branch Row

private struct BranchRow: View {
    let branch: String
    let isCurrentBranch: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppConfig.UI.largeSpacing) {
                Image(systemName: isCurrentBranch ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: AppConfig.UI.largePadding))
                    .foregroundStyle(isCurrentBranch ? Color.blue : Color.secondary)

                Text(branch)
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(AppConfig.UI.largeSpacing)
            .background(isCurrentBranch ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrentBranch)
    }
}

#Preview {
    BranchSelectorSheet(
        currentBranch: "main",
        branches: ["main", "develop", "feature/test"],
        onSelect: { _ in }
    )
}
