//
//  BrowserInstancesSheet.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 浏览器实例列表弹窗
/// 显示所有运行中的浏览器实例
struct BrowserInstancesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let instances: [ChromeInstance]

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text("运行中的浏览器实例")
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
            if instances.isEmpty {
                emptyStateView
            } else {
                instanceListView
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: AppConfig.UI.extraLargeSpacing) {
            Image(systemName: "globe")
                .font(.system(size: AppConfig.UI.iconContainerSize))
                .foregroundStyle(.secondary)

            Text("没有运行中的浏览器实例")
                .font(.system(size: AppConfig.UI.mediumFontSize + 1))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instance List View

    private var instanceListView: some View {
        ScrollView {
            VStack(spacing: AppConfig.UI.largeSpacing) {
                ForEach(instances) { instance in
                    InstanceDetailCard(instance: instance)
                }
            }
            .padding(AppConfig.UI.extraLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Instance Detail Card

/// 实例详情卡片
struct InstanceDetailCard: View {
    let instance: ChromeInstance

    var body: some View {
        HStack(spacing: AppConfig.UI.extraLargeSpacing) {
            instanceIcon
            instanceInfo
            Spacer()
        }
        .padding(AppConfig.UI.largePadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Instance Icon

    private var instanceIcon: some View {
        Image(systemName: "globe")
            .font(.system(size: AppConfig.UI.iconSize))
            .foregroundStyle(.blue)
            .frame(width: 40, height: 40)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Instance Info

    private var instanceInfo: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
            Text(instance.processName)
                .font(.system(size: AppConfig.UI.mediumFontSize + 1, weight: .medium))

            if !instance.url.isEmpty {
                Text(instance.url)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: AppConfig.UI.largeSpacing) {
                Label("PID: \(instance.id)", systemImage: "number")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)

                if let debugPort = instance.debugPort {
                    Label("端口: \(debugPort)", systemImage: "network")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

#Preview {
    BrowserInstancesSheet(instances: [])
}
