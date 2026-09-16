//
//  ADBDeployView.swift
//  Techne
//
//  Created by SlippinDylan on 2026/03/10.
//

import SwiftUI
import Observation
import UniformTypeIdentifiers

struct ADBDeployView: View {
    @Bindable var viewModel: ADBDeployViewModel
    private let deployControlOuterHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. 设备状态卡片 (顶部固定)
            deviceInfoCard
            
            // 2. APK 部署操作区 + 实时输出
            deployOperationCard

            Spacer(minLength: 0)
        }
        .padding(24)
        .navigationTitle("安卓应用部署")
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    // MARK: - Device Info Card
    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("设备状态", systemImage: "macbook.and.iphone")

            GroupBox {
                HStack(spacing: 20) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 48))
                        .foregroundStyle(viewModel.device != nil ? Color.accentColor : .secondary)
                        .frame(width: 80, height: 80)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let device = viewModel.device {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(device.brand) \(device.model)")
                                .font(.headline)
                            Group {
                                Text("Android 版本: \(device.androidVersion) (SDK \(device.sdkVersion))")
                                Text("序列号: \(device.serial)")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("未检测到设备，请检查 USB 连接并确保开启开发者模式")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Combined Deploy Operation Card
    private var deployOperationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: AppConfig.UI.mediumSpacing) {
                sectionHeader("安装操作", systemImage: "paperplane")
                Spacer()

                if !viewModel.terminalOutput.isEmpty {
                    consoleActions
                }
            }

            GroupBox {
                VStack(spacing: 0) {
                    deployControlsSection
                        .padding(AppConfig.UI.largePadding)

                    Divider()
                        .padding(.horizontal, AppConfig.UI.largePadding)

                    consoleSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppConfig.UI.largePadding)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var deployControlsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                InteractivePathField(
                    leadingSystemImage: "doc.badge.plus",
                    text: viewModel.selectedAPK?.url.path,
                    placeholder: "点击选择或拖入 APK 文件...",
                    height: deployControlOuterHeight,
                    action: { viewModel.selectAPK() },
                    onDropProviders: handleAPKDrop(providers:)
                ) {
                    if let apk = viewModel.selectedAPK {
                        Text(apk.formattedSize)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)

                CleanMyMacButton(
                    title: "立即部署",
                    icon: "arrow.down.doc.fill",
                    action: {
                        guard canDeploy else { return }
                        viewModel.deploy()
                    },
                    style: .primary,
                    isDestructive: false
                )
                .allowsHitTesting(canDeploy)
            }

            if viewModel.status != .idle {
                VStack(spacing: 8) {
                    HStack {
                        Text(viewModel.status.description)
                            .font(.caption)
                        Spacer()
                        if case .failure = viewModel.status {
                            Button("重置") { viewModel.status = .idle }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                        }
                    }

                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(statusColor)
                }
            }
        }
    }

    // MARK: - Console Section
    private var consoleSection: some View {
        EmbeddedConsoleSection(
            output: viewModel.terminalOutput,
            emptyText: "等待任务启动...",
            outerPadding: 0
        )
    }

    private var consoleActions: some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Button("复制日志") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.terminalOutput, forType: .string)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button("清除日志") { viewModel.clearTerminal() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    // MARK: - Helpers
    private var progressValue: Double {
        switch viewModel.status {
        case .idle: return 0
        case .parsingAPK: return 0.1
        case .cleaning: return 0.3
        case .installing: return 0.6
        case .launching: return 0.9
        case .success: return 1.0
        case .failure: return 1.0
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .success: return .green
        case .failure: return .red
        default: return .accentColor
        }
    }

    private var canDeploy: Bool {
        viewModel.device != nil &&
        viewModel.selectedAPK != nil &&
        (viewModel.status == .idle || viewModel.status == .success)
    }

    private func handleAPKDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?

            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let itemURL = item as? URL {
                url = itemURL
            } else {
                url = nil
            }

            guard let fileURL = url, fileURL.pathExtension.lowercased() == "apk" else {
                return
            }

            Task { @MainActor in
                viewModel.selectAPKFile(at: fileURL)
            }
        }

        return true
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

#Preview {
    ADBDeployView(viewModel: ADBDeployViewModel())
}
