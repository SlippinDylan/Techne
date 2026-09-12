//
//  DiscoveredServerCard.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 自动发现的服务器卡片
/// 显示新发现的服务器，带有"新发现"角标和"添加"按钮
struct DiscoveredServerCard: View {
    let server: DevServer
    let relatedInstances: [ChromeInstance]
    let onAdd: () -> Void
    let onKillServer: () -> Void
    let onKillInstance: (ChromeInstance) -> Void

    @Environment(BrowserDetectionService.self) private var browserDetectionService
    @State private var showingBrowserSelector = false
    @State private var currentBranch: String?
    private let browserLaunchService = BrowserLaunchService()

    var body: some View {
        AppPanelCard {
            VStack(spacing: 0) {
                serverInfoSection

                if !relatedInstances.isEmpty {
                    Divider()
                        .padding(.horizontal, AppConfig.UI.largePadding)
                    relatedInstancesList
                }
            }
        }
        .sheet(isPresented: $showingBrowserSelector) {
            BrowserSelectorSheet(
                browsers: browserDetectionService.installedBrowsers,
                onSelect: { browser in
                    await launchInBrowser(browser: browser)
                }
            )
        }
        .task {
            // 异步加载分支信息，避免阻塞主线程
            if !server.projectPath.isEmpty {
                currentBranch = await Task.detached {
                    GitService.shared.getCurrentBranch(at: server.projectPath)
                }.value
            }
        }
    }

    // MARK: - Server Info Section

    private var serverInfoSection: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            serverIcon
            serverDetails
            Spacer()
            actionButtons
        }
        .padding(AppConfig.UI.largePadding)
    }

    // MARK: - Server Icon

    private var serverIcon: some View {
        Image(systemName: server.serverType.icon)
            .font(.system(size: AppConfig.UI.iconSize))
            .foregroundStyle(.green)
            .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
            .background(.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Server Details

    private var serverDetails: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            serverNameAndBadge
            pathAndBranchInfo
            serverAddressInfo
        }
    }

    private var serverNameAndBadge: some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Text(server.projectName)
                .font(.system(size: AppConfig.UI.mediumFontSize + 2, weight: .semibold))

            Text("新发现")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .padding(.horizontal, AppConfig.UI.mediumSpacing)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.1))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
        }
    }

    private var pathAndBranchInfo: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            if !server.projectPath.isEmpty {
                ClickablePathLabel(path: server.projectPath)

                if let branch = currentBranch {
                    HStack(spacing: AppConfig.UI.smallSpacing) {
                        Image(systemName: "arrow.branch")
                            .font(.system(size: AppConfig.UI.smallFontSize))
                        Text(branch)
                            .font(.system(size: AppConfig.UI.smallFontSize))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var serverAddressInfo: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            Button(action: presentBrowserSelector) {
                HStack(spacing: AppConfig.UI.smallSpacing) {
                    Image(systemName: "network")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                    Text("localhost:\(String(server.port))")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Label("PID: \(String(server.id))", systemImage: "number")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            addButton

            ActionButton(
                icon: "terminal",
                action: openInTerminal,
                tooltip: "在终端打开",
                isDisabled: server.projectPath.isEmpty
            )

            ActionButton(
                icon: "xmark.circle.fill",
                action: onKillServer,
                tooltip: "关闭服务器",
                isDestructive: true
            )
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            HStack(spacing: AppConfig.UI.smallSpacing) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: AppConfig.UI.smallIconSize))
                Text("添加")
                    .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))
            }
        }
        .adaptiveGlassProminentButtonStyle()
        .buttonBorderShape(.capsule)
    }

    // MARK: - Related Instances List

    private var relatedInstancesList: some View {
        ForEach(relatedInstances) { instance in
            BrowserInstanceRow(
                instance: instance,
                onKill: { onKillInstance(instance) }
            )
        }
    }

    // MARK: - Helper Methods

    private func openInTerminal() {
        guard !server.projectPath.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", server.projectPath]

        do {
            try task.run()
        } catch {
            LogService.shared.error("打开终端失败: \(error.localizedDescription)", category: "终端")
        }
    }

    private func presentBrowserSelector() {
        browserDetectionService.refresh()
        showingBrowserSelector = true
    }

    private func launchInBrowser(
        browser: Browser
    ) async -> Result<Void, Error> {
        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: server.port,
            projectPath: server.projectPath,
            shouldOpenURL: true,
            launchSource: "discovered-server"
        )

        let result = await browserLaunchService.launchBrowser(request)

        switch result {
        case .success(let pid):
            LogService.shared.success("成功启动浏览器实例 (PID: \(pid))", category: "浏览器")
            return .success(())
        case .failure(let error):
            LogService.shared.error("启动浏览器失败: \(error.localizedDescription)", category: "浏览器")
            return .failure(error)
        }
    }
}

#Preview {
    DiscoveredServerCard(
        server: DevServer(
            id: 12345,
            processName: "node",
            port: 3000,
            projectPath: "/Users/test/project",
            projectName: "Test Server",
            serverType: .vite,
            commandLine: "node server.js"
        ),
        relatedInstances: [],
        onAdd: {},
        onKillServer: {},
        onKillInstance: { _ in }
    )
    .environment(BrowserDetectionService())
    .padding()
}
