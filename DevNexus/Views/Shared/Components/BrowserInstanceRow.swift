//
//  BrowserInstanceRow.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 浏览器实例行组件
/// 用于显示单个浏览器实例的信息，可复用于多个地方
struct BrowserInstanceRow: View {
    let instance: ChromeInstance
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            instanceIcon
            instanceInfo
            Spacer()
            killButton
        }
        .padding(AppConfig.UI.largePadding)
    }

    // MARK: - Instance Icon

    private var instanceIcon: some View {
        Group {
            if let appIcon = instance.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: AppConfig.UI.mediumIconSize, height: AppConfig.UI.mediumIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: AppConfig.UI.smallIconSize))
                    .foregroundStyle(.green)
                    .frame(width: AppConfig.UI.mediumIconSize, height: AppConfig.UI.mediumIconSize)
                    .background(.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            }
        }
    }

    // MARK: - Instance Info

    private var instanceInfo: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
            Text(instance.processName)
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))

            HStack(spacing: AppConfig.UI.largeSpacing) {
                if !instance.url.isEmpty {
                    Label(instance.url, systemImage: "link")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let debugPort = instance.debugPort {
                    Label("调试端口: \(debugPort)", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Kill Button

    private var killButton: some View {
        ActionButton(
            icon: "xmark.circle.fill",
            action: onKill,
            tooltip: "关闭实例",
            isDestructive: true
        )
    }
}

#Preview {
    VStack {
        BrowserInstanceRow(
            instance: ChromeInstance(
                id: 12345,
                processName: "Google Chrome",
                url: "http://localhost:3000",
                debugPort: 9222,
                commandLine: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                startTime: Date()
            ),
            onKill: {}
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }
    .padding()
}
