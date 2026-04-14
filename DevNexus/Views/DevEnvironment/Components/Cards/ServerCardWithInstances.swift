//
//  ServerCardWithInstances.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 服务器卡片（带关联的浏览器实例）
/// 显示已添加的服务器及其关联的浏览器实例
struct ServerCardWithInstances: View {
    let server: DevServer
    let relatedInstances: [ChromeInstance]
    let onKillServer: () -> Void
    let onKillInstance: (ChromeInstance) -> Void

    @State private var showingBrowserSelector = false
    @State private var browsers: [Browser] = []
    private let browserDetectionService = BrowserDetectionService()
    private let browserLaunchService = BrowserLaunchService()

    var body: some View {
        VStack(spacing: 0) {
            serverInfoSection

            if !relatedInstances.isEmpty {
                Divider()
                    .padding(.horizontal, AppConfig.UI.largePadding)
                relatedInstancesList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
        .sheet(isPresented: $showingBrowserSelector) {
            BrowserSelectorSheet(
                url: "http://localhost:\(server.port)",
                browsers: browsers,
                onSelect: { browser in
                    launchInBrowser(browser: browser)
                    showingBrowserSelector = false
                }
            )
        }
        .task {
            browsers = browserDetectionService.detectInstalledBrowsers()
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
            .font(.system(size: AppConfig.UI.mediumIconSize))
            .foregroundStyle(.blue)
            .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Server Details

    private var serverDetails: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            serverNameAndType

            if !server.projectPath.isEmpty {
                ClickablePathLabel(path: server.projectPath)
            }

            serverMetadata
        }
    }

    private var serverNameAndType: some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Text(server.projectName)
                .font(.system(size: AppConfig.UI.mediumFontSize + 2, weight: .semibold))

            Text(server.serverType.rawValue)
                .font(.system(size: AppConfig.UI.smallFontSize))
                .padding(.horizontal, AppConfig.UI.mediumSpacing)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
        }
    }

    private var serverMetadata: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            Label("localhost:\(String(server.port))", systemImage: "network")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)

            Label("PID: \(String(server.id))", systemImage: "number")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            ActionButton(
                icon: "safari",
                action: { showingBrowserSelector = true },
                tooltip: "在浏览器中打开"
            )

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
            LogService.shared.error("在终端打开失败: \(error.localizedDescription)", category: "终端")
        }
    }

    private func launchInBrowser(browser: Browser) {
        let url = "http://localhost:\(server.port)"
        Task {
            let result = await browserLaunchService.launchBrowser(
                browserPath: browser.path,
                url: url,
                debugPort: 0
            )

            switch result {
            case .success(let pid):
                LogService.shared.success("成功启动浏览器 (PID: \(pid))", category: "浏览器")
            case .failure(let error):
                LogService.shared.error("启动浏览器失败: \(error.localizedDescription)", category: "浏览器")
            }
        }
    }
}

#Preview {
    ServerCardWithInstances(
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
        onKillServer: {},
        onKillInstance: { _ in }
    )
    .padding()
}
