//
//  ProjectListView.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI

/// 统一的项目列表视图
/// 根据 projectType 参数显示不同类型的项目
struct ProjectListView: View {
    let projectType: ProjectType

    @Environment(ProjectService.self) private var projectService
    @Environment(DevServerDetectionService.self) private var devServerService
    @Environment(ChromeDetectionService.self) private var chromeService
    @Environment(BrowserDetectionService.self) private var browserDetectionService
    @State private var showingAddSheet = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var projectToRemove: Project?
    @State private var showingKillAllServersAlert = false
    @State private var showingKillAllInstancesAlert = false
    @State private var showingBrowserInstances = false

    var body: some View {
        presentedContent
            .onReceive(NotificationCenter.default.publisher(for: .addDevProject)) { _ in
                if projectType == .devServer { showingAddSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .addMiniAppProject)) { _ in
                if projectType == .miniApp { showingAddSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .devServerProcessStarted)) { notification in
                guard projectType == .devServer else { return }
                guard let userInfo = notification.userInfo,
                      let pid = userInfo["pid"] as? Int32 else { return }
                devServerService.refreshUntilServerDetected(pid: pid)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devServerStopped)) { _ in
                guard projectType == .devServer else { return }
                devServerService.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .browserDidOpen)) { _ in
                guard projectType == .devServer else { return }
                chromeService.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .browserInstancesChanged)) { _ in
                guard projectType == .devServer else { return }
                chromeService.refresh()
            }
            .onChange(of: devServerService.servers.map(\.id)) { _, _ in
                projectService.reconcileDetectedDevServers(devServerService.servers)
            }
            .task {
                guard projectType == .devServer else { return }
                browserDetectionService.refreshIfNeeded()
            }
    }

    private var projectContent: some View {
        VStack(spacing: 0) {
            // 固定的统计卡片区域
            statisticsSection
                .padding(AppConfig.UI.extraLargePadding)

            // 可滚动的内容区域
            if filteredProjects.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
    }

    private var presentedContent: some View {
        projectContent
        .sheet(isPresented: $showingAddSheet) {
            AddProjectSheet(projectType: projectType) { path in
                projectService.addProject(path: path, type: projectType)
            }
        }
        .confirmationDialog(
            "确定要移除项目吗？",
            isPresented: Binding(
                get: { projectToRemove != nil },
                set: { if !$0 { projectToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                if let project = projectToRemove {
                    projectService.removeProject(project)
                }
            }
        } message: {
            if let project = projectToRemove {
                Text("项目 '\(project.name)' 将从列表中移除，但不会删除磁盘上的文件。")
            }
        }
        .alert("错误", isPresented: $showingError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingBrowserInstances) {
            BrowserInstancesSheet(instances: allBrowserInstances)
        }
        .alert("确认关闭所有服务器", isPresented: $showingKillAllServersAlert) {
            Button("取消", role: .cancel) { }
            Button("全部关闭", role: .destructive) {
                devServerService.killAllServers()
            }
        } message: {
            Text("确定要关闭所有运行中的本地服务吗？")
        }
        .alert("确认关闭所有实例", isPresented: $showingKillAllInstancesAlert) {
            Button("取消", role: .cancel) { }
            Button("全部关闭", role: .destructive) {
                chromeService.killAllInstances()
            }
        } message: {
            Text("确定要关闭所有 \(allBrowserInstances.count) 个浏览器实例吗？此操作不可撤销。")
        }
    }

    // MARK: - Subviews

    private var statisticsSection: some View {
        HStack(spacing: AppConfig.UI.largePadding) {
            StatCard(
                icon: "folder",
                label: "已添加项目",
                value: "\(filteredProjects.count)",
                iconColor: .blue
            )
            StatCard(
                icon: "play.circle",
                label: "运行中项目",
                value: "\(filteredProjects.filter { $0.isRunning || findRelatedServer(for: $0) != nil }.count)",
                iconColor: .green
            )
            StatCard(
                icon: "doc.badge.ellipsis",
                label: "未提交变更",
                value: "\(filteredProjects.reduce(0) { $0 + $1.uncommittedFileCount })",
                iconColor: .orange
            )
            
            if projectType == .devServer {
                StatCard(
                    icon: "globe",
                    label: "运行中的实例",
                    value: "\(allBrowserInstances.count)",
                    iconColor: .blue,
                    isClickable: true,
                    action: { showingBrowserInstances = true }
                )
            } else {
                StatCard(
                    icon: "app.badge",
                    label: "微信工具",
                    value: "READY",
                    iconColor: .green
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: projectType == .devServer ? "server.rack" : "app.badge")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text(projectType == .devServer ? "暂无开发项目" : "暂无小程序项目")
                .font(.title2)
                .bold()
            
            Text(projectType == .devServer ? "点击右上角 + 按钮添加开发项目" : "点击右上角 + 按钮添加微信小程序项目")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: AppConfig.UI.extraLargePadding) {
                // 项目列表
                if !filteredProjects.isEmpty {
                    projectsListSection
                }
            }
            .padding(AppConfig.UI.extraLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectsListSection: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumPadding) {
            HStack {
                Label("我的项目", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                
                Spacer()
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: AppConfig.UI.largePadding) {
                ForEach(filteredProjects) { project in
                    ProjectCard(
                        project: project,
                        relatedServer: findRelatedServer(for: project),
                        relatedInstances: getRelatedInstances(for: findRelatedServer(for: project)),
                        onRemove: { projectToRemove = project },
                        onSwitchBranch: { switchBranch(for: project, to: $0) },
                        onDiscardChanges: { _ = projectService.discardChanges(at: project.path) },
                        onStartServer: { startServer(for: project) },
                        onStopServer: { stopServer(for: project) },
                        onSwitchStartupMode: { switchStartupMode(for: project, to: $0) },
                        onRefresh: { refreshProject(project) },
                        onKillServer: { 
                            if let server = findRelatedServer(for: project) {
                                _ = devServerService.killServer(server)
                            }
                        },
                        onKillInstance: { _ = chromeService.killInstance($0) },
                        onCardTap: { /* 小程序项目点击卡片暂无特定全局动作，内部会处理跳转 */ }
                    )
                }
            }
        }
    }

    // MARK: - Logic & Actions

    private var filteredProjects: [Project] {
        projectService.projects.filter { $0.type == projectType }
    }

    private var allBrowserInstances: [ChromeInstance] {
        chromeService.instances
    }

    private func findRelatedServer(for project: Project) -> DevServer? {
        let managedProjectPaths = filteredProjects.map(\.path)
        let normalizedProjectPath = normalizedPath(for: project.path)

        if let runningProcessPID = project.runningProcessPID,
           let pidMatchedServer = devServerService.servers.first(where: { server in
               server.id == runningProcessPID
                   && DevServerProjectMatcher.bestMatchingProjectPath(
                       for: server,
                       managedProjectPaths: managedProjectPaths
                   ) == normalizedProjectPath
           }) {
            return pidMatchedServer
        }

        return devServerService.servers.first { server in
            DevServerProjectMatcher.bestMatchingProjectPath(
                for: server,
                managedProjectPaths: managedProjectPaths
            ) == normalizedProjectPath
        }
    }

    private func normalizedPath(for path: String) -> String {
        DevServerProjectMatcher.normalize(path)
    }

    private func getRelatedInstances(for server: DevServer?) -> [ChromeInstance] {
        guard let server = server else { return [] }
        return chromeService.instances.filter { $0.isRelated(to: server) }
    }

    private func refreshProject(_ project: Project) {
        projectService.refreshProjectStatusAsync(at: project.path)
    }

    private func switchBranch(for project: Project, to branch: String) {
        let wasRunning = project.isRunning || (projectType == .devServer && findRelatedServer(for: project) != nil)
        Task {
            if projectType == .miniApp && project.isRunning {
                _ = await projectService.stopServer(for: project)
            }
            let autoStart = projectType == .devServer ? wasRunning : false
            let result = await projectService.switchBranch(at: project.path, to: branch, autoStart: autoStart)
            switch result {
            case .success: break
            case .failure(let error):
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func startServer(for project: Project) {
        _ = projectService.startServer(for: project)
    }

    private func stopServer(for project: Project) {
        Task {
            _ = await projectService.stopServer(for: project)
        }
    }

    private func switchStartupMode(for project: Project, to modeID: String) {
        Task {
            let result = await projectService.switchStartupMode(for: project, to: modeID)
            if case .failure(let error) = result {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

}

#Preview {
    let commandConfigService = CommandConfigService()
    ProjectListView(projectType: .devServer)
        .environment(ProjectService(commandConfigService: commandConfigService))
        .environment(DevServerDetectionService())
        .environment(ChromeDetectionService())
        .environment(BrowserDetectionService())
}
