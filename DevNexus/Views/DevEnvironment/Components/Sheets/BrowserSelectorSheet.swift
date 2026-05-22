//
//  BrowserSelectorSheet.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

fileprivate enum BrowserSelectorLayout {
    static let sheetWidth: CGFloat = 760
    static let cardMinHeight: CGFloat = 108
    static let cardIconSize: CGFloat = 36
    static let maxColumns = 4
}

/// 浏览器选择器弹窗
/// 用于为开发服务选择浏览器实例
struct BrowserSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let browsers: [Browser]
    let onSelect: @Sendable (Browser) async -> Result<Void, Error>
    @State private var launchingBrowserID: Browser.ID?
    @State private var launchErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(width: BrowserSelectorLayout.sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text("选择浏览器")
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
        VStack(alignment: .leading, spacing: AppConfig.UI.extraLargeSpacing) {
            if let launchErrorMessage {
                errorBanner(message: launchErrorMessage)
            }

            if browsers.isEmpty {
                emptyStateView
            } else {
                browserGridView
            }
        }
        .padding(AppConfig.UI.extraLargePadding)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: AppConfig.UI.mediumSpacing) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("当前 Mac 上未检测到可启动的受支持浏览器")
                .font(.system(size: AppConfig.UI.mediumFontSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
    }

    // MARK: - Browser Grid View

    private var browserGridView: some View {
        let columnCount = min(max(browsers.count, 1), BrowserSelectorLayout.maxColumns)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: AppConfig.UI.largeSpacing),
            count: columnCount
        )

        return LazyVGrid(columns: columns, spacing: AppConfig.UI.mediumSpacing) {
            ForEach(browsers) { browser in
                BrowserCardButton(
                    browser: browser,
                    isDisabled: isLaunching,
                    showsLaunchingOverlay: launchingBrowserID == browser.id
                ) {
                    launch(browser)
                }
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        Text(message)
            .font(.system(size: AppConfig.UI.smallFontSize))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConfig.UI.mediumPadding)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
    }

    private func launch(_ browser: Browser) {
        launchingBrowserID = browser.id
        launchErrorMessage = nil

        Task {
            let result = await onSelect(browser)

            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    launchingBrowserID = nil
                    launchErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private var isLaunching: Bool {
        launchingBrowserID != nil
    }
}

// MARK: - Browser Card Button

/// 浏览器卡片按钮
private struct BrowserCardButton: View {
    let browser: Browser
    let isDisabled: Bool
    let showsLaunchingOverlay: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppConfig.UI.mediumSpacing) {
                browserIcon

                VStack(spacing: 4) {
                    Text(browser.displayName)
                        .font(.system(size: AppConfig.UI.mediumFontSize))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if browser.isDefault {
                        Text("默认浏览器")
                            .font(.system(size: AppConfig.UI.smallFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: BrowserSelectorLayout.cardMinHeight)
            .padding(AppConfig.UI.mediumPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
            .overlay {
                if showsLaunchingOverlay {
                    RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius)
                        .fill(Color.black.opacity(0.38))
                        .overlay {
                            VStack(spacing: AppConfig.UI.mediumSpacing) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("正在启动…")
                                    .font(.system(size: AppConfig.UI.smallFontSize, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                }
            }
            .opacity(isDisabled && showsLaunchingOverlay == false ? 0.58 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }

    private var browserIcon: some View {
        Group {
            if let appIcon = browser.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: BrowserSelectorLayout.cardIconSize,
                        height: BrowserSelectorLayout.cardIconSize
                    )
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: BrowserSelectorLayout.cardIconSize))
                    .foregroundStyle(.blue)
            }
        }
    }
}

#Preview {
    BrowserSelectorSheet(
        browsers: [],
        onSelect: { _ in .success(()) }
    )
}
