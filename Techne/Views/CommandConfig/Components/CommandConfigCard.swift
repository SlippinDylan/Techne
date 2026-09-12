//
//  CommandConfigCard.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

struct CommandConfigCard: View {
    let config: CommandConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppConfig.UI.largePadding) {
                configIcon
                configDetails
                Spacer()
                actionButtons
            }
            .padding(AppConfig.UI.largePadding)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Config Icon

    private var configIcon: some View {
        Image(systemName: "terminal.fill")
            .font(.system(size: AppConfig.UI.iconSize))
            .foregroundStyle(.blue)
            .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Config Details

    private var configDetails: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            HStack(spacing: AppConfig.UI.mediumSpacing) {
                Text(config.name)
                    .font(.system(size: AppConfig.UI.mediumFontSize + 2, weight: .semibold))

                Text(config.projectType.displayName)
                    .font(.system(size: AppConfig.UI.smallFontSize, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, AppConfig.UI.mediumSpacing)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            }

            commandsList
        }
    }

    private var commandsList: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
            if !config.startCommand.isEmpty {
                commandRow(label: "启动", command: config.startCommand)
            }
            if !config.buildCommand.isEmpty {
                commandRow(label: "编译", command: config.buildCommand)
            }
            if !config.cleanCommand.isEmpty {
                commandRow(label: "清理", command: config.cleanCommand)
            }
            if !config.discardChangesCommand.isEmpty {
                commandRow(label: "丢弃更改", command: config.discardChangesCommand)
            }
            if !config.installCommand.isEmpty {
                commandRow(label: "安装依赖", command: config.installCommand)
            }
            if !config.stopCommand.isEmpty {
                commandRow(label: "停止", command: config.stopCommand)
            }
        }
    }

    private func commandRow(label: String, command: String) -> some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Text(label + ":")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(command)
                .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            ActionButton(
                icon: "square.and.pencil",
                action: onEdit,
                tooltip: "编辑配置"
            )

            ActionButton(
                icon: "trash",
                action: onDelete,
                tooltip: "删除配置",
                isDestructive: true
            )
        }
    }
}

#Preview {
    CommandConfigCard(
        config: CommandConfig.vitePnpm,
        onEdit: {},
        onDelete: {}
    )
    .padding()
}
