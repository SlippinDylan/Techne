//
//  AddProjectSheet.swift
//  DevNexus
//
//  统一的添加项目弹窗
//  支持开发服务和小程序两种类型
//

import SwiftUI
import UniformTypeIdentifiers

/// 统一的添加项目弹窗
/// 根据 projectType 参数显示不同的标题和配置过滤
struct AddProjectSheet: View {
    let projectType: ProjectType
    let onAdd: (String, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CommandConfigService.self) var commandConfigService

    @State private var projectPath = ""
    @State private var selectedConfigId: UUID?
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            formView
        }
        .frame(width: 700, height: 500)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    projectPath = url.path
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text(projectType == .devServer ? "添加开发项目" : "添加小程序项目")
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

    // MARK: - Form View

    private var formView: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.extraLargeSpacing) {
            projectPathField
            commandConfigSection

            Spacer()

            actionButtons
        }
        .padding(AppConfig.UI.extraLargePadding)
    }

    // MARK: - Project Path Field

    private var projectPathField: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            Text("项目路径")
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))

            HStack(spacing: AppConfig.UI.mediumSpacing) {
                TextField("请输入项目路径", text: $projectPath)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, AppConfig.UI.mediumPadding)
                    .frame(height: 44)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .overlay(
                        Button(action: { showingFilePicker = true }) {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    )
            }
        }
    }

    // MARK: - Command Config Section

    private var commandConfigSection: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            Text("命令配置")
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))

            if filteredConfigs.isEmpty {
                emptyConfigView
            } else {
                configCardsView
            }
        }
    }

    private var emptyConfigView: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("暂无命令配置")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Text("可以先直接添加项目，后续在项目卡片中查看命令详情")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppConfig.UI.extraLargePadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    private var configCardsView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: AppConfig.UI.mediumSpacing),
                GridItem(.flexible(), spacing: AppConfig.UI.mediumSpacing)
            ], spacing: AppConfig.UI.mediumSpacing) {
                ForEach(filteredConfigs) { config in
                    ConfigSelectionCard(
                        config: config,
                        isSelected: selectedConfigId == config.id,
                        onSelect: {
                            selectedConfigId = config.id
                        }
                    )
                }
            }
            .padding(AppConfig.UI.largePadding)
        }
        .frame(maxHeight: 250)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Spacer()

            Button(action: { dismiss() }) {
                Text("取消")
            }
            .adaptiveGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)

            Button(action: {
                onAdd(projectPath, selectedConfigId)
            }) {
                Text("添加")
            }
            .adaptiveGlassProminentButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .disabled(projectPath.isEmpty)
        }
    }

    // MARK: - Computed Properties

    private var filteredConfigs: [CommandConfig] {
        let configs = commandConfigService.configs.filter { $0.projectType == projectType }
        guard projectType == .miniApp else { return configs }

        return configs.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = configPriority(lhs.element)
                let rhsPriority = configPriority(rhs.element)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func configPriority(_ config: CommandConfig) -> Int {
        let fields = [
            config.name,
            config.startCommand,
            config.buildCommand,
            config.installCommand
        ]
        let containsPnpm = fields.contains { $0.localizedCaseInsensitiveContains("pnpm") }
        return containsPnpm ? 0 : 1
    }

}

// MARK: - Config Selection Card

struct ConfigSelectionCard: View {
    let config: CommandConfig
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
                // 配置图标和名称
                HStack(spacing: AppConfig.UI.mediumSpacing) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))

                    Text(config.name)
                        .font(.system(size: AppConfig.UI.mediumFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()
                }

                // 命令列表
                commandsList
            }
            .padding(AppConfig.UI.largePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius)
                    .stroke(isSelected ? Color.blue : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var commandsList: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        HStack(spacing: 8) {
            Text(label + ":")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    AddProjectSheet(projectType: .devServer, onAdd: { _, _ in })
        .environment(CommandConfigService())
}
