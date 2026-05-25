//
//  CommandConfigView.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

struct CommandConfigView: View {
    @Environment(CommandConfigService.self) var commandConfigService
    @State private var showingAddConfig = false
    @State private var showingEditConfig: CommandConfig? = nil
    @State private var showingDeleteAlert: CommandConfig? = nil

    var body: some View {
        VStack(spacing: 0) {
            if commandConfigService.configs.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddCommandConfig"))) { _ in
            showingAddConfig = true
        }
        .sheet(isPresented: $showingAddConfig) {
            CommandConfigEditSheet(
                config: nil,
                onSave: { config in
                    _ = commandConfigService.addConfig(config)
                    showingAddConfig = false
                }
            )
        }
        .sheet(item: $showingEditConfig) { config in
            CommandConfigEditSheet(
                config: config,
                onSave: { updatedConfig in
                    switch commandConfigService.updateConfig(updatedConfig) {
                    case .success:
                        showingEditConfig = nil
                    case .failure(let error):
                        LogService.shared.error("更新配置失败: \(error.localizedDescription)", category: "命令配置")
                    }
                }
            )
        }
        .alert(item: $showingDeleteAlert) { config in
            Alert(
                title: Text("确认删除"),
                message: Text("确定要删除配置 \"\(config.name)\" 吗？此操作不可撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    commandConfigService.removeConfig(config)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            VStack(spacing: AppConfig.UI.largeSpacing) {
                ForEach(commandConfigService.configs) { config in
                    CommandConfigCard(
                        config: config,
                        onEdit: {
                            showingEditConfig = config
                        },
                        onDelete: {
                            showingDeleteAlert = config
                        }
                    )
                }
            }
            .padding(AppConfig.UI.extraLargePadding)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: AppConfig.UI.largePadding) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("没有命令配置")
                .font(.system(size: 20, weight: .medium))

            Text("点击\"添加配置\"创建新的命令配置模板")
                .font(.system(size: AppConfig.UI.mediumFontSize))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CommandConfigView()
        .environment(CommandConfigService())
}
