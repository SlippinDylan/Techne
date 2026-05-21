//
//  BrowserSelectorSheet.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 浏览器选择器弹窗
/// 用于选择浏览器打开指定 URL
struct BrowserSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: String?
    let browsers: [Browser]
    let onSelect: @Sendable (Browser, Bool) async -> Result<Void, Error>
    @State private var shouldOpenURL = true
    @State private var isLaunching = false
    @State private var launchErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(width: 500, height: 400)
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
        ScrollView {
            VStack(alignment: .leading, spacing: AppConfig.UI.extraLargeSpacing) {
                Text(url.map { "打开 \($0)" } ?? "启动独立浏览器实例")
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .foregroundStyle(.secondary)

                if url != nil {
                    Toggle("启动后打开当前地址", isOn: $shouldOpenURL)
                        .disabled(isLaunching)
                }

                if isLaunching {
                    ProgressView("正在启动浏览器...")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                }

                if let launchErrorMessage {
                    Text(launchErrorMessage)
                        .font(.system(size: AppConfig.UI.smallFontSize))
                        .foregroundStyle(.red)
                }

                if browsers.isEmpty {
                    emptyStateView
                } else {
                    browserGridView
                }
            }
            .padding(AppConfig.UI.extraLargePadding)
        }
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
        let columnCount = browsers.count == 1 ? 1 : 2
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: AppConfig.UI.largeSpacing),
            count: columnCount
        )

        return LazyVGrid(columns: columns, spacing: AppConfig.UI.mediumSpacing) {
            ForEach(browsers) { browser in
                BrowserCardButton(browser: browser, isDisabled: isLaunching) {
                    launch(browser)
                }
            }
        }
    }

    private func launch(_ browser: Browser) {
        isLaunching = true
        launchErrorMessage = nil

        Task {
            let result = await onSelect(browser, shouldOpenURL)

            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    isLaunching = false
                    launchErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Browser Card Button

/// 浏览器卡片按钮
private struct BrowserCardButton: View {
    let browser: Browser
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppConfig.UI.mediumSpacing) {
                browserIcon

                VStack(spacing: 4) {
                    Text(browser.displayName)
                        .font(.system(size: AppConfig.UI.mediumFontSize))
                        .foregroundStyle(.primary)

                    if browser.isDefault {
                        Text("默认浏览器")
                            .font(.system(size: AppConfig.UI.smallFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 132)
            .padding(AppConfig.UI.largePadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
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
                    .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: AppConfig.UI.iconContainerSize))
                    .foregroundStyle(.blue)
            }
        }
    }
}

#Preview {
    BrowserSelectorSheet(
        url: "http://localhost:3000",
        browsers: [],
        onSelect: { _, _ in .success(()) }
    )
}
