//
//  CommandConfigEditSheet.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

struct CommandConfigEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let config: CommandConfig?
    let onSave: (CommandConfig) -> Void

    @State private var name: String
    @State private var projectType: ProjectType
    @State private var startCommand: String
    @State private var buildCommand: String
    @State private var cleanCommand: String
    @State private var discardChangesCommand: String
    @State private var installCommand: String
    @State private var stopCommand: String

    init(config: CommandConfig?, onSave: @escaping (CommandConfig) -> Void) {
        self.config = config
        self.onSave = onSave

        _name = State(initialValue: config?.name ?? "")
        _projectType = State(initialValue: config?.projectType ?? .devServer)
        _startCommand = State(initialValue: config?.startCommand ?? "")
        _buildCommand = State(initialValue: config?.buildCommand ?? "")
        _cleanCommand = State(initialValue: config?.cleanCommand ?? "")
        _discardChangesCommand = State(initialValue: config?.discardChangesCommand ?? "")
        _installCommand = State(initialValue: config?.installCommand ?? "")
        _stopCommand = State(initialValue: config?.stopCommand ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 600, height: 700)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text(config == nil ? "添加命令配置" : "编辑命令配置")
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
            VStack(alignment: .leading, spacing: AppConfig.UI.largePadding) {
                // 配置名称（必填）
                VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
                    Text("配置名称")
                        .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))
                    TextField("例如：Vite + pnpm", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, AppConfig.UI.mediumPadding)
                        .frame(height: 28)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                }
                Divider()
                // 项目类型（必填）
                VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
                    Picker("项目类型", selection: $projectType) {
                        ForEach(ProjectType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                }

                Divider()

                // 启动命令
                commandField(
                    title: "启动命令",
                    placeholder: "例如：pnpm dev",
                    text: $startCommand,
                    description: "用于启动开发服务器"
                )

                // 编译命令
                commandField(
                    title: "编译命令",
                    placeholder: "例如：pnpm build",
                    text: $buildCommand,
                    description: "用于构建生产版本"
                )

                // 清理缓存命令
                commandField(
                    title: "清理缓存命令",
                    placeholder: "例如：rm -rf dist node_modules/.cache",
                    text: $cleanCommand,
                    description: "用于清除编译产物和缓存"
                )

                // 丢弃更改命令
                commandField(
                    title: "丢弃更改命令",
                    placeholder: "例如：git reset --hard && git clean -fd",
                    text: $discardChangesCommand,
                    description: "用于丢弃工作区的所有更改"
                )

                // 安装依赖命令
                commandField(
                    title: "安装依赖命令",
                    placeholder: "例如：pnpm install",
                    text: $installCommand,
                    description: "用于安装项目依赖"
                )

                // 停止命令
                commandField(
                    title: "停止命令",
                    placeholder: "通常留空，使用 kill 命令",
                    text: $stopCommand,
                    description: "用于停止服务器（可选）"
                )
            }
            .padding(AppConfig.UI.extraLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commandField(title: String, placeholder: String, text: Binding<String>, description: String) -> some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))
                Text("(\(description))")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                .padding(.horizontal, AppConfig.UI.mediumPadding)
                .frame(height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Button("取消") {
                dismiss()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("保存") {
                saveConfig()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.defaultAction)
            .disabled(name.isEmpty)
        }
        .padding(AppConfig.UI.extraLargePadding)
    }

    // MARK: - Actions

    private func saveConfig() {
        let newConfig = CommandConfig(
            id: config?.id ?? UUID(),
            name: name,
            projectType: projectType,
            startCommand: startCommand,
            buildCommand: buildCommand,
            cleanCommand: cleanCommand,
            discardChangesCommand: discardChangesCommand,
            installCommand: installCommand,
            stopCommand: stopCommand
        )
        onSave(newConfig)
    }
}

#Preview {
    CommandConfigEditSheet(config: nil, onSave: { _ in })
}
