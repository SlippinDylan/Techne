//
//  AddProjectSheet.swift
//  DevNexus
//
//  统一的添加项目弹窗
//

import SwiftUI
import UniformTypeIdentifiers

struct AddProjectSheet: View {
    let projectType: ProjectType
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var projectPath = ""
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
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            projectPath = url.path
        }
    }

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
            .buttonStyle(.plain)
        }
        .padding(AppConfig.UI.extraLargePadding)
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.extraLargeSpacing) {
            projectPathField
            commandSnapshotSection

            Spacer()

            actionButtons
        }
        .padding(AppConfig.UI.extraLargePadding)
    }

    private var projectPathField: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            Text("项目路径")
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))

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
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                )
        }
    }

    private var commandSnapshotSection: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            Text("命令快照")
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))

            VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
                Text("添加后会根据项目类型、lockfile 和 package.json scripts 自动生成完整的项目命令快照。")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)

                Text("不会再写入命令模板卡片；项目卡片里展示的就是项目自身命令。")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)

                if let snapshot = snapshotPreview {
                    Divider()
                    snapshotRows(snapshot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConfig.UI.largePadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
        }
    }

    private func snapshotRows(_ snapshot: ProjectCommandSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
            Text(snapshot.commandProfileName)
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .semibold))

            previewRow("启动", snapshot.startCommand)
            previewRow("安装依赖", snapshot.installCommand)
            previewRow("构建", snapshot.buildCommand)
            previewRow("清理", snapshot.cleanCommand)
            previewRow("停止", snapshot.stopCommand)
            previewRow("丢弃更改", snapshot.discardChangesCommand)
        }
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Spacer()

            Button("取消") {
                dismiss()
            }
            .adaptiveGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)

            Button("添加") {
                onAdd(projectPath)
            }
            .adaptiveGlassProminentButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .disabled(projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var snapshotPreview: ProjectCommandSnapshot? {
        let trimmedPath = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        return ProjectCommandSnapshotResolver.resolvedSnapshot(for: projectType, path: trimmedPath)
    }
}

#Preview {
    AddProjectSheet(projectType: .devServer, onAdd: { _ in })
}
