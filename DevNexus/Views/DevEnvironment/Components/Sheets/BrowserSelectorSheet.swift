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
    let url: String
    let browsers: [Browser]
    let onSelect: (Browser) -> Void

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
                Text("打开 \(url)")
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .foregroundStyle(.secondary)

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
        Text("未检测到已安装的浏览器")
            .font(.system(size: AppConfig.UI.mediumFontSize))
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
    }

    // MARK: - Browser Grid View

    private var browserGridView: some View {
        let columns = [
            GridItem(.flexible(), spacing: AppConfig.UI.largeSpacing),
            GridItem(.flexible(), spacing: AppConfig.UI.largeSpacing)
        ]

        return LazyVGrid(columns: columns, spacing: AppConfig.UI.mediumSpacing) {
            ForEach(browsers) { browser in
                BrowserCardButton(browser: browser) {
                    onSelect(browser)
                }
            }
        }
    }
}

// MARK: - Browser Card Button

/// 浏览器卡片按钮
private struct BrowserCardButton: View {
    let browser: Browser
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppConfig.UI.mediumSpacing) {
                browserIcon

                Text(browser.displayName)
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppConfig.UI.largePadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
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
        onSelect: { _ in }
    )
}
