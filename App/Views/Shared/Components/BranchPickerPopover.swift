import SwiftUI

struct BranchPickerPopover: View {
    let viewModel: BranchPickerViewModel
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.largeSpacing) {
            headerView

            Divider()

            contentView

            if viewModel.showsPaginationControls {
                Divider()
                paginationView
            }
        }
        .padding(AppConfig.UI.largePadding)
        .frame(width: 320)
    }

    private var headerView: some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Label("切换分支", systemImage: "arrow.branch")
                .font(.headline)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.visibleBranches.isEmpty {
            emptyStateView
        } else {
            VStack(spacing: AppConfig.UI.smallSpacing) {
                ForEach(viewModel.visibleBranches, id: \.self) { branch in
                    branchRow(branch)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: AppConfig.UI.mediumSpacing) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(AppLocalized(viewModel.isLoading ? "正在加载分支..." : "未检测到本地分支"))
                .font(.system(size: AppConfig.UI.mediumFontSize))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
    }

    private func branchRow(_ branch: String) -> some View {
        let isCurrentBranch = branch == viewModel.currentBranch

        return Button {
            guard isCurrentBranch == false else { return }
            onSelect(branch)
        } label: {
            HStack(spacing: AppConfig.UI.mediumSpacing) {
                Image(systemName: isCurrentBranch ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .foregroundStyle(isCurrentBranch ? Color.accentColor : Color.secondary)

                Text(branch)
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppConfig.UI.mediumPadding)
            .padding(.vertical, AppConfig.UI.mediumSpacing)
            .background(rowBackground(isCurrentBranch: isCurrentBranch))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isCurrentBranch)
    }

    private func rowBackground(isCurrentBranch: Bool) -> some ShapeStyle {
        if isCurrentBranch {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }

        return AnyShapeStyle(Color.secondary.opacity(0.08))
    }

    private var paginationView: some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Button {
                viewModel.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.hasPreviousPage == false)

            Text(viewModel.pageIndicator)
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48)

            Button {
                viewModel.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.hasNextPage == false)

            Spacer()
        }
    }
}

#Preview {
    let viewModel = BranchPickerViewModel(
        projectPath: "/Users/test/project",
        currentBranch: "main",
        snapshotLoader: { _ in
            BranchPickerSnapshot(currentBranch: "main", branches: ["main", "develop", "feature/a"])
        }
    )
    viewModel.replaceCachedBranches(["main", "develop", "feature/a"])

    return BranchPickerPopover(viewModel: viewModel, onSelect: { _ in })
        .padding()
}
