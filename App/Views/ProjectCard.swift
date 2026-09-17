//
//  ProjectCard.swift
//  Techne
//
//  统一的项目卡片
//  支持开发服务和小程序两种类型
//

import SwiftUI

/// 统一的项目卡片
/// 根据 project.type 显示不同内容
struct ProjectCard: View {
    let project: Project
    let relatedServer: DevServer?
    let relatedInstances: [ChromeInstance]
    let onRemove: () -> Void
    let onSwitchBranch: (String) -> Void
    let onDiscardChanges: () -> Void
    let onStartServer: () -> Void
    let onStopServer: () -> Void
    let onRestartServer: () -> Void
    let onSwitchStartupMode: (String) -> Void
    let onRefresh: () -> Void
    let onKillServer: () -> Void
    let onKillInstance: (ChromeInstance) -> Void
    let onCardTap: () -> Void

    @Environment(ProjectService.self) var projectService
    @Environment(BrowserDetectionService.self) private var browserDetectionService
    @State private var branchPickerViewModel: BranchPickerViewModel
    @State private var showingBranchPicker = false
    @State private var showingRemoveAlert = false
    @State private var showingDiscardAlert = false
    @State private var showingBrowserSelector = false
    @State private var showingCommandDetails = false
    @State private var isProjectTerminalExpanded = true
    private let browserLaunchService = BrowserLaunchService()

    init(
        project: Project,
        relatedServer: DevServer?,
        relatedInstances: [ChromeInstance],
        onRemove: @escaping () -> Void,
        onSwitchBranch: @escaping (String) -> Void,
        onDiscardChanges: @escaping () -> Void,
        onStartServer: @escaping () -> Void,
        onStopServer: @escaping () -> Void,
        onRestartServer: @escaping () -> Void,
        onSwitchStartupMode: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onKillServer: @escaping () -> Void,
        onKillInstance: @escaping (ChromeInstance) -> Void,
        onCardTap: @escaping () -> Void
    ) {
        self.project = project
        self.relatedServer = relatedServer
        self.relatedInstances = relatedInstances
        self.onRemove = onRemove
        self.onSwitchBranch = onSwitchBranch
        self.onDiscardChanges = onDiscardChanges
        self.onStartServer = onStartServer
        self.onStopServer = onStopServer
        self.onRestartServer = onRestartServer
        self.onSwitchStartupMode = onSwitchStartupMode
        self.onRefresh = onRefresh
        self.onKillServer = onKillServer
        self.onKillInstance = onKillInstance
        self.onCardTap = onCardTap
        _branchPickerViewModel = State(
            wrappedValue: BranchPickerViewModel(
                projectPath: project.path,
                currentBranch: project.currentBranch
            )
        )
    }

    var body: some View {
        AppPanelCard {
            VStack(spacing: 0) {
                projectInfoSection

                if project.uncommittedFileCount > 0 {
                    Divider()
                        .padding(.horizontal, AppConfig.UI.largePadding)
                    workingDirectoryWarning
                }

                // 开发服务：显示浏览器实例
                if project.type == .devServer && !relatedInstances.isEmpty {
                    Divider()
                        .padding(.horizontal, AppConfig.UI.largePadding)
                    relatedInstancesList
                }

                if shouldShowProjectTerminalSection {
                    Divider()
                        .padding(.horizontal, AppConfig.UI.largePadding)
                    terminalOutputView
                }
            }
        }
        .sheet(isPresented: $showingBrowserSelector) {
            if let server = relatedServer {
                BrowserSelectorSheet(
                    browsers: browserDetectionService.installedBrowsers,
                    onSelect: { browser in
                        await launchInBrowser(browser: browser, port: server.port)
                    }
                )
            }
        }
        .alert("确认移除项目", isPresented: $showingRemoveAlert) {
            Button("取消", role: .cancel) { }
            Button("移除", role: .destructive) {
                onRemove()
            }
        } message: {
            Text("确定要从列表中移除\"\(project.name)\"吗？这不会删除项目文件。")
        }
        .alert("确认放弃更改", isPresented: $showingDiscardAlert) {
            Button("取消", role: .cancel) { }
            Button("放弃更改", role: .destructive) {
                onDiscardChanges()
                updateStatus()
            }
        } message: {
            Text("确定要放弃所有未提交的更改吗？此操作不可撤销。")
        }
        .task {
            branchPickerViewModel.updateProjectContext(path: project.path, currentBranch: project.currentBranch)
            updateStatus()
        }
        .onChange(of: project.path) { _, newPath in
            branchPickerViewModel.updateProjectContext(path: newPath, currentBranch: project.currentBranch)
        }
        .onChange(of: project.currentBranch) { _, newCurrentBranch in
            branchPickerViewModel.updateProjectContext(path: project.path, currentBranch: newCurrentBranch)
        }
    }

    // MARK: - Project Info Section

    private var projectInfoSection: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            projectIcon
            projectDetails
            Spacer()
            actionButtons
        }
        .padding(AppConfig.UI.largePadding)
    }

    // MARK: - Project Icon

    private var projectIcon: some View {
        Group {
            if isTransitioning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: AppConfig.UI.iconSize))
                    .foregroundStyle(isRunning ? Color.green : Color.blue)
            }
        }
        .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
        .background((isRunning ? Color.green : Color.blue).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
        .onTapGesture {
            if project.type == .devServer {
                onRefresh()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(AppConfig.UI.refreshDelay))
                    updateStatus()
                }
            } else {
                onCardTap()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(AppConfig.UI.refreshDelay))
                    updateStatus()
                }
            }
        }
    }

    private var iconName: String {
        switch project.type {
        case .devServer:
            return isRunning ? "square.stack.3d.down.right.fill" : "square.stack.3d.down.right"
        case .miniApp:
            return isRunning ? "app.badge.fill" : "app.badge"
        }
    }

    // MARK: - Project Details

    private var projectDetails: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            projectNameAndStatus
            projectMetadata
            if project.type == .devServer {
                serverInfo
            }
        }
    }

    private var projectNameAndStatus: some View {
        HStack(spacing: AppConfig.UI.mediumSpacing) {
            Text(project.name)
                .font(.system(size: AppConfig.UI.mediumFontSize + 2, weight: .semibold))

            Button(commandDetails.profileDisplayName) {
                showingCommandDetails = true
            }
            .font(.system(size: AppConfig.UI.smallFontSize))
            .padding(.horizontal, AppConfig.UI.mediumSpacing)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
            .buttonStyle(.plain)
            .popover(isPresented: $showingCommandDetails, arrowEdge: .top) {
                ProjectCommandDetailsPopover(project: project)
            }

            if project.type == .devServer, project.availableStartupModes.count > 1 {
                StartupModePicker(
                    modes: project.availableStartupModes,
                    selectedModeID: project.selectedStartupModeID,
                    isDisabled: isTransitioning,
                    onSelect: onSwitchStartupMode
                )
            }

            if let statusLabel = transitionStatusLabel {
                Text(statusLabel)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .padding(.horizontal, AppConfig.UI.mediumSpacing)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
            } else if isRunning {
                Text("运行中")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .padding(.horizontal, AppConfig.UI.mediumSpacing)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
            }
        }
    }

    private var projectMetadata: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            ClickablePathLabel(path: project.path)

            ClickableBranchLabel(
                branchName: project.currentBranch.isEmpty ? "未知分支" : project.currentBranch,
                onTap: {
                    branchPickerViewModel.updateProjectContext(path: project.path, currentBranch: project.currentBranch)
                    showingBranchPicker = true
                    branchPickerViewModel.open()
                }
            )
            .popover(isPresented: $showingBranchPicker, arrowEdge: .top) {
                BranchPickerPopover(
                    viewModel: branchPickerViewModel,
                    onSelect: { branch in
                        showingBranchPicker = false
                        onSwitchBranch(branch)
                    }
                )
            }

            if project.uncommittedFileCount > 0 {
                Label("\(project.uncommittedFileCount) 个未提交的文件", systemImage: "doc.badge.ellipsis")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var serverInfo: some View {
        let displayPID: String
        if let pid = project.runningProcessPID {
            displayPID = "PID: \(pid)"
        } else if let server = relatedServer {
            displayPID = "PID: \(server.id)"
        } else {
            displayPID = "PID: -"
        }

        return HStack(spacing: AppConfig.UI.largePadding) {
            if let server = relatedServer {
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
            } else {
                Label("localhost:-", systemImage: "network")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)
            }

            Label(displayPID, systemImage: "number")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            // 如果检测到关联的服务器或项目标记为运行中，显示停止按钮
            if isTransitioning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else if isRunning {
                ActionButton(
                    icon: "arrow.clockwise",
                    action: onRestartServer,
                    tooltip: "重新启动"
                )
                ActionButton(
                    icon: "stop.fill",
                    action: onStopServer,
                    tooltip: "停止服务器"
                )
            } else {
                ActionButton(
                    icon: "play.fill",
                    action: onStartServer,
                    tooltip: "启动服务器"
                )
            }

            if shouldShowProjectTerminalToggle {
                ActionButton(
                    icon: "rectangle.bottomthird.inset.filled",
                    action: { isProjectTerminalExpanded.toggle() },
                    tooltip: "显示或隐藏日志"
                )
            }

            ActionButton(
                icon: "terminal",
                action: openInTerminal,
                tooltip: "在终端打开"
            )

            ActionButton(
                icon: "trash",
                action: { showingRemoveAlert = true },
                tooltip: "移除项目",
                isDestructive: true
            )
        }
    }

    // MARK: - Working Directory Warning

    private var workingDirectoryWarning: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: AppConfig.UI.largePadding))
                .foregroundStyle(.orange)

            Text("工作目录有 \(project.uncommittedFileCount) 个未提交的文件")
                .font(.system(size: AppConfig.UI.mediumFontSize))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: { showingDiscardAlert = true }) {
                Text("放弃更改")
                    .font(.system(size: AppConfig.UI.smallFontSize, weight: .medium))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(.red)
        }
        .padding(AppConfig.UI.largePadding)
    }

    // MARK: - Related Instances List (DevServer only)

    private var relatedInstancesList: some View {
        ForEach(relatedInstances) { instance in
            BrowserInstanceRow(
                instance: instance,
                onKill: { onKillInstance(instance) }
            )
        }
    }

    // MARK: - Terminal Output View

    private var terminalOutputView: some View {
        EmbeddedConsoleSection(
            output: project.terminalOutput,
            emptyText: "等待任务启动...",
            height: ConsolePanelStyle.embeddedTerminalViewportHeight
        )
    }

    // MARK: - Helper Properties

    private var isRunning: Bool {
        relatedServer != nil || project.isRunning
    }

    private var terminalVisibilityProject: Project {
        var project = project
        project.isRunning = isRunning
        return project
    }

    private var isTransitioning: Bool {
        project.transitionState != .idle
    }

    private var commandDetails: ProjectCommandDetails {
        ProjectCommandDetails(project: project)
    }

    private var shouldShowProjectTerminalToggle: Bool {
        ProjectTerminalVisibility.showsToggle(for: terminalVisibilityProject)
    }

    private var shouldShowProjectTerminalSection: Bool {
        shouldShowProjectTerminalToggle && isProjectTerminalExpanded
    }

    private var transitionStatusLabel: String? {
        switch project.transitionState {
        case .idle:
            return nil
        case .installing:
            return "安装中"
        case .starting:
            return "启动中"
        case .stopping:
            return "停止中"
        }
    }

    // MARK: - Helper Methods

    private func openInTerminal() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", project.path]
        try? task.run()
    }

    private func presentBrowserSelector() {
        browserDetectionService.refresh()
        showingBrowserSelector = true
    }

    private func launchInBrowser(
        browser: Browser,
        port: Int
    ) async -> Result<Void, Error> {
        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: port,
            projectPath: project.path,
            shouldOpenURL: true,
            launchSource: "project-card"
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

    private func updateStatus() {
        let projectId = project.id
        let projectPath = project.path

        Task.detached {
            // 在后台线程执行 git 操作
            let gitService = GitService.shared
            let newStatus = gitService.getWorkingDirectoryStatus(at: projectPath)
            let newCurrentBranch = gitService.getCurrentBranch(at: projectPath)

            await MainActor.run { [weak projectService] in
                guard let projectService else { return }

                // 更新项目模型中的 uncommittedFileCount 和 currentBranch
                if let index = projectService.projects.firstIndex(where: { $0.id == projectId }) {
                    projectService.projects[index].uncommittedFileCount = newStatus.fileCount
                    if let branch = newCurrentBranch {
                        projectService.projects[index].currentBranch = branch
                    }
                }
            }
        }
    }
}

#Preview {
    ProjectCard(
        project: Project(
            name: "Test Project",
            path: "/Users/test/project",
            type: .devServer,
            currentBranch: "main"
        ),
        relatedServer: DevServer(
            id: 12345,
            processName: "node",
            port: 3000,
            projectPath: "/Users/test/project",
            projectName: "Test Server",
            serverType: .vite,
            commandLine: "node server.js"
        ),
        relatedInstances: [],
        onRemove: {},
        onSwitchBranch: { _ in },
        onDiscardChanges: {},
        onStartServer: {},
        onStopServer: {},
        onRestartServer: {},
        onSwitchStartupMode: { _ in },
        onRefresh: {},
        onKillServer: {},
        onKillInstance: { _ in },
        onCardTap: {}
    )
    .environment(ProjectService(commandConfigService: CommandConfigService()))
    .environment(BrowserDetectionService())
    .padding()
}
