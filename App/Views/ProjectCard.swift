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
    let onResetMiniAppFileWatching: () -> Void
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
    @State private var isDiscardHovered = false
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
        onResetMiniAppFileWatching: @escaping () -> Void,
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
        self.onResetMiniAppFileWatching = onResetMiniAppFileWatching
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
            VStack(spacing: AppConfig.UI.mediumPadding) {
                projectInfoSection

                if project.uncommittedFileCount > 0 {
                    workingDirectoryWarning
                }

                // 开发服务：显示浏览器实例
                if project.type == .devServer && !relatedInstances.isEmpty {
                    relatedInstancesList
                }

                if shouldShowProjectTerminalSection {
                    terminalOutputView
                }
            }
            .padding(AppConfig.UI.largePadding)
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
            Text(AppLocalizedFormat("确定要从列表中移除\"%@\"吗？这不会删除项目文件。", project.name))
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
                    .foregroundStyle(Color.blue)
            }
        }
        .frame(width: AppConfig.UI.iconContainerSize, height: AppConfig.UI.iconContainerSize)
        .background(Color.blue.opacity(0.1))
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

            ClickableBranchLabel(
                branchName: project.currentBranch.isEmpty ? AppLocalized("未知分支") : project.currentBranch,
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
            HStack(spacing: AppConfig.UI.smallSpacing) {
                ClickablePathLabel(path: project.path)

                ActionButton(
                    icon: "terminal",
                    action: openInTerminal,
                    tooltip: AppLocalized("在终端打开"),
                    presentation: .grouped
                )
            }

            if project.type == .devServer {
                serverInfo
            }
        }
    }

    private var serverInfo: some View {
        let displayPID: String
        if let pid = project.runningProcessPID {
            displayPID = AppLocalizedFormat("PID: %lld", Int64(pid))
        } else if let server = relatedServer {
            displayPID = AppLocalizedFormat("PID: %lld", Int64(server.id))
        } else {
            displayPID = AppLocalized("PID: -")
        }

        return HStack(spacing: AppConfig.UI.largePadding) {
            if let server = relatedServer {
                Button(action: presentBrowserSelector) {
                    HStack(spacing: AppConfig.UI.smallSpacing) {
                        Image(systemName: "network")
                            .font(.system(size: AppConfig.UI.smallFontSize))
                        Text(AppLocalizedFormat("localhost: %lld", Int64(server.port)))
                            .font(.system(size: AppConfig.UI.smallFontSize))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            } else {
                Label(AppLocalized("localhost: -"), systemImage: "network")
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
        HStack(spacing: 0) {
            // 如果检测到关联的服务器或项目标记为运行中，显示停止按钮
            if isTransitioning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
                actionButtonDivider
            } else if isRunning {
                ActionButton(
                    icon: "restart",
                    action: onRestartServer,
                    tooltip: AppLocalized("重新启动"),
                    presentation: .grouped
                )
                ActionButton(
                    icon: "stop.fill",
                    action: onStopServer,
                    tooltip: AppLocalized("停止服务器"),
                    presentation: .grouped
                )
                actionButtonDivider
            } else {
                ActionButton(
                    icon: "play.fill",
                    action: onStartServer,
                    tooltip: AppLocalized("启动服务器"),
                    presentation: .grouped
                )
                actionButtonDivider
            }

            if project.type == .miniApp {
                ActionButton(
                    icon: "folder.badge.gearshape",
                    action: onResetMiniAppFileWatching,
                    tooltip: AppLocalized("重建微信文件监听"),
                    presentation: .grouped
                )
            }

            if shouldShowProjectTerminalToggle {
                ActionButton(
                    icon: "apple.terminal.on.rectangle",
                    action: { isProjectTerminalExpanded.toggle() },
                    tooltip: AppLocalized("显示或隐藏日志"),
                    presentation: .grouped
                )
            }

            if project.type == .miniApp || shouldShowProjectTerminalToggle {
                actionButtonDivider
            }

            if project.type == .miniApp {
                ActionButton(
                    icon: "arrow.clockwise",
                    action: onRefresh,
                    tooltip: AppLocalized("刷新状态"),
                    presentation: .grouped
                )
                actionButtonDivider
            }

            ActionButton(
                icon: "trash",
                action: { showingRemoveAlert = true },
                tooltip: AppLocalized("移除项目"),
                isDestructive: true,
                presentation: .grouped
            )
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var actionButtonDivider: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 2)
    }

    // MARK: - Working Directory Warning

    private var workingDirectoryWarning: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: AppConfig.UI.largePadding))
                .foregroundStyle(.orange)

            Text(AppLocalizedFormat("工作目录有 %lld 个未提交的文件", Int64(project.uncommittedFileCount)))
                .font(.system(size: AppConfig.UI.mediumFontSize))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: { showingDiscardAlert = true }) {
                Text("放弃更改")
                    .font(.system(size: AppConfig.UI.smallFontSize, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, AppConfig.UI.mediumPadding)
                    .padding(.vertical, AppConfig.UI.smallSpacing)
                    .background(
                        Color.red.opacity(isDiscardHovered ? 0.12 : 0),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isDiscardHovered = hovering
            }
        }
        .padding(AppConfig.UI.mediumPadding)
        .background(
            Color.orange.opacity(0.06),
            in: RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius)
        )
    }

    // MARK: - Related Instances List (DevServer only)

    private var relatedInstancesList: some View {
        VStack(spacing: 0) {
            ForEach(relatedInstances) { instance in
                BrowserInstanceRow(
                    instance: instance,
                    onKill: { onKillInstance(instance) }
                )
            }
        }
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius)
        )
    }

    // MARK: - Terminal Output View

    private var terminalOutputView: some View {
        EmbeddedConsoleSection(
            output: project.terminalOutput,
            emptyText: AppLocalized("等待任务启动..."),
            height: ConsolePanelStyle.embeddedTerminalViewportHeight,
            outerPadding: 0
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
            return AppLocalized("安装中")
        case .starting:
            return AppLocalized("启动中")
        case .stopping:
            return AppLocalized("停止中")
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
            LogService.shared.success(AppLocalizedFormat("成功启动浏览器实例 (PID: %lld)", Int64(pid)), category: AppLocalized("浏览器"))
            return .success(())
        case .failure(let error):
            LogService.shared.error(AppLocalizedFormat("启动浏览器失败: %@", error.localizedDescription), category: AppLocalized("浏览器"))
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
        onResetMiniAppFileWatching: {},
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
