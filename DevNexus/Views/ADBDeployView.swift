//
//  ADBDeployView.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/03/10.
//

import SwiftUI
import Observation
import UniformTypeIdentifiers

struct ADBDeployView: View {
    @Bindable var viewModel: ADBDeployViewModel

    private let deployControlOuterHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. 设备状态卡片 (顶部固定)
            deviceInfoCard
            
            // 2. APK 部署操作区 (顶部固定)
            deployOperationCard
            
            // 3. 控制台输出 (弹性撑满剩余空间)
            consoleSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .navigationTitle("安卓应用部署")
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    // MARK: - Device Info Card
    private var deviceInfoCard: some View {
        GroupBox(label: Label("设备状态", systemImage: "macbook.and.iphone")) {
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

    // MARK: - Combined Deploy Operation Card
    private var deployOperationCard: some View {
        GroupBox(label: Label("安装操作", systemImage: "paperplane")) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    // 左侧：路径显示/点击区域 (模拟 Liquid Glass 风格的输入框容器)
                    Button(action: { viewModel.selectAPK() }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .foregroundStyle(Color.accentColor)
                            
                            if let apk = viewModel.selectedAPK {
                                Text(apk.url.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                Text("点击选择或拖入 APK 文件...")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            if let apk = viewModel.selectedAPK {
                                Text(apk.formattedSize)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: deployControlOuterHeight, maxHeight: deployControlOuterHeight)
                    .buttonStyle(.plain)
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                        handleAPKDrop(providers: providers)
                    }
                    
                    // 右侧：部署按钮 (使用 Prominent 玻璃样式)
                    Button(action: {
                        guard canDeploy else { return }
                        viewModel.deploy()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc.fill")
                            Text("立即部署")
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    .adaptiveGlassProminentButtonStyle()
                    .controlSize(.small)
                    .frame(width: 100, height: deployControlOuterHeight)
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
                                    .adaptiveGlassButtonStyle()
                                    .controlSize(.small)
                            }
                        }
                        
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(statusColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Console Section
    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("实时输出", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if !viewModel.terminalOutput.isEmpty {
                    Button("复制日志") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.terminalOutput, forType: .string)
                    }
                    .adaptiveGlassButtonStyle()
                    .controlSize(.small)

                    Button("清除日志") { viewModel.clearTerminal() }
                        .adaptiveGlassButtonStyle()
                        .controlSize(.small)
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.terminalOutput.isEmpty ? "等待任务启动..." : viewModel.terminalOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(viewModel.terminalOutput.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .onChange(of: viewModel.terminalOutput) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .padding(.top, 8)
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
}

#Preview {
    ADBDeployView(viewModel: ADBDeployViewModel())
}
