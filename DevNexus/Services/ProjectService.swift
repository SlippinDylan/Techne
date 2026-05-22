//
//  ProjectService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation
import Observation

/// 统一的项目服务 (Step 4 任务熔断重构版)
/// 
/// 依据：
/// 1. 使用 Task 引用配合 cancel() 实现协作式取消，替代传统的布尔锁。
/// 2. 在耗时计算循环中显式检查 Task.isCancelled 以节省系统资源。
@Observable
final class ProjectService {
    // MARK: - @MainActor 隔离的 UI 状态

    @MainActor var projects: [Project] = []
    @MainActor var isLoading = false
    
    // MARK: - Task 4: 任务熔断锁
    @MainActor private var currentRefreshTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let gitService = GitService.shared
    private let processService = ProcessService.shared
    private let persistenceService: PersistenceService<Project>
    private let logService = LogService.shared
    private let operationsManager = ProjectOperationsManager()
    private let processManager = ProcessManager()
    private let terminalHandler = TerminalOutputHandler()
    private let commandConfigService: CommandConfigService
    private let managedBrowserInstanceService: ManagedBrowserInstanceService

    private var gitMonitors: [String: GitWorkspaceMonitor] = [:]
    private var cachedProcessKeywords: [String]?
    private var devServerDetectionTriggeredProjectIDs: Set<UUID> = []

    // MARK: - Initialization

    @MainActor
    init(
        commandConfigService: CommandConfigService,
        managedBrowserInstanceService: ManagedBrowserInstanceService = ManagedBrowserInstanceService(),
        persistenceService: PersistenceService<Project> = PersistenceService(filename: "projects.json")
    ) {
        self.commandConfigService = commandConfigService
        self.managedBrowserInstanceService = managedBrowserInstanceService
        self.persistenceService = persistenceService
        loadProjects()
    }

    // MARK: - Status Refresh (异步任务熔断架构)

    /// 刷新所有项目状态
    func refreshAll() {
        Task { @MainActor in
            // 1. 取消旧任务 (协作式熔断)
            currentRefreshTask?.cancel()
            
            isLoading = true
            let currentProjects = projects
            let keywords = getProcessKeywords()
            
            // 2. 开启新任务
            currentRefreshTask = Task.detached(priority: .userInitiated) { [weak self] in
                var updated = currentProjects
                
                for i in 0..<updated.count {
                    // MARK: - 依据：在每一轮耗时计算前检查取消标志
                    if Task.isCancelled { return }
                    
                    let status = await BackgroundWorker.shared.getProjectStatus(path: updated[i].path, keywords: keywords, pid: updated[i].runningProcessPID)
                    updated[i].currentBranch = status.branch
                    updated[i].uncommittedFileCount = status.fileCount
                    updated[i].isRunning = status.isRunning
                }
                
                // 最终提交前再次确认
                if Task.isCancelled { return }
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.projects = updated
                    self.isLoading = false
                    self.currentRefreshTask = nil
                }
            }
        }
    }

    func refreshAllProjectsStatus() { refreshAll() }
    func refreshAllWorkingDirectoryStatus() { refreshAll() }
    func refreshAllProjectsStatusAsync() { refreshAll() }
    func refreshAllWorkingDirectoryStatusAsync() { refreshAll() }

    /// 单个项目刷新 (不受全局熔断影响)
    nonisolated func refreshProjectStatusAsync(at path: String) {
        Task { @MainActor in
            guard let project = self.projects.first(where: { $0.path == path }) else { return }
            let keywords = getProcessKeywords()
            let pid = project.runningProcessPID
            
            Task.detached(priority: .utility) {
                let status = await BackgroundWorker.shared.getProjectStatus(path: path, keywords: keywords, pid: pid)
                
                await MainActor.run {
                    if let index = self.projects.firstIndex(where: { $0.path == path }) {
                        self.projects[index].currentBranch = status.branch
                        self.projects[index].uncommittedFileCount = status.fileCount
                        self.projects[index].isRunning = status.isRunning
                    }
                }
            }
        }
    }

    // MARK: - Project Management (@MainActor)

    @MainActor
    func addProject(path: String, type: ProjectType, configId: UUID? = nil) -> Result<Project, ProjectServiceError> {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.pathNotFound(path))
        }
        if ProjectPersistenceMigration.isTemporaryProjectPath(path) {
            return .failure(.invalidConfiguration("临时目录项目不会被持久化，请选择真实项目目录"))
        }
        if projects.contains(where: { $0.path == path }) {
            return .failure(.projectAlreadyExists(path))
        }
        let projectName = URL(fileURLWithPath: path).lastPathComponent
        let commandConfig = configId.flatMap(commandConfigService.getConfig(by:))
        let project = ProjectCommandSnapshotResolver.makeProject(
            name: projectName,
            path: path,
            type: type,
            commandConfigId: configId,
            legacyConfig: commandConfig
        )
        projects.append(project)
        saveProjects()
        
        Task {
            await setupMonitor(for: project)
            refreshProjectStatusAsync(at: path)
        }
        return .success(project)
    }

    @MainActor
    func removeProject(_ project: Project) {
        let path = project.path
        if let monitor = gitMonitors[path] {
            monitor.stop()
        }
        gitMonitors.removeValue(forKey: path)
        projects.removeAll { $0.id == project.id }
        saveProjects()
    }

    @MainActor
    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            let oldPath = projects[index].path
            projects[index] = project
            saveProjects()
            if oldPath != project.path {
                if let monitor = gitMonitors[oldPath] {
                    monitor.stop()
                }
                gitMonitors.removeValue(forKey: oldPath)
                Task {
                    await setupMonitor(for: project)
                }
            }
        }
    }

    @MainActor
    func replaceProjectsForImport(_ projects: [Project]) {
        applyPersistenceMigration(projects: projects)
        synchronizeMonitorsWithProjects()
        refreshAll()
    }

    @MainActor
    func mergeImportedProjects(_ imported: [Project]) {
        let mergedProjects = BackupService.mergeProjects(existing: projects, incoming: imported)
        applyPersistenceMigration(projects: mergedProjects)
        synchronizeMonitorsWithProjects()
        refreshAll()
    }

    // MARK: - Monitor Management

    private func setupMonitorsForAllProjects() {
        Task { @MainActor in
            for project in projects {
                await setupMonitor(for: project)
            }
        }
    }

    @MainActor
    private func synchronizeMonitorsWithProjects() {
        let activePaths = Set(projects.map(\.path))
        let stalePaths = gitMonitors.keys.filter { !activePaths.contains($0) }

        for stalePath in stalePaths {
            gitMonitors[stalePath]?.stop()
            gitMonitors.removeValue(forKey: stalePath)
        }

        setupMonitorsForAllProjects()
    }

    private func setupMonitor(for project: Project) async {
        if let existing = gitMonitors[project.path] {
            existing.stop()
        }
        
        let path = project.path
        let monitor = GitWorkspaceMonitor(path: path) { [weak self] in
            self?.refreshProjectStatusAsync(at: path)
        }
        monitor.start()
        gitMonitors[path] = monitor
    }

    // MARK: - Git & Process Logic

    @MainActor
    func discardChanges(at path: String) -> Result<Void, ProjectServiceError> {
        guard let project = projects.first(where: { $0.path == path }) else { return .failure(.pathNotFound(path)) }
        return operationsManager.discardChanges(at: path, projectName: project.name, category: getCategoryName(for: project.type))
    }

    @MainActor
    func switchBranch(at path: String, to branch: String, autoStart: Bool = true) async -> Result<Void, ProjectServiceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.path == path }) else { return .failure(.pathNotFound(path)) }
        let project = projects[projectIndex]
        let cleanCommand = cleanCommand(for: project)
        
        let result = await operationsManager.switchBranch(
            at: path, 
            to: branch, 
            projectName: project.name, 
            category: getCategoryName(for: project.type), 
            cleanCommand: cleanCommand, 
            stopProcess: { await stopServer(for: project) }, 
            startProcess: { startServer(for: project) }, 
            autoStart: autoStart, 
            onStatusUpdate: { [weak self] count in 
                Task { @MainActor in
                    if let idx = self?.projects.firstIndex(where: { $0.path == path }) {
                        self?.projects[idx].uncommittedFileCount = count 
                    }
                }
            }
        )
        
        if case .success = result {
            projects[projectIndex].currentBranch = branch
            saveProjects()
        }
        return result
    }

    @MainActor
    func switchStartupMode(for project: Project, to modeID: String) async -> Result<Void, ProjectServiceError> {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return .failure(.pathNotFound(project.path))
        }
        guard projects[index].availableStartupModes.contains(where: { $0.id == modeID }) else {
            return .failure(.invalidConfiguration("无效的启动模式"))
        }

        let wasRunning = projects[index].isRunning || projects[index].runningProcessPID != nil
        projects[index].selectStartupMode(id: modeID)
        let updatedProject = projects[index]
        saveProjects()
        appendSystemTerminalMessage(
            "已切换启动模式为 \(updatedProject.selectedStartupMode?.displayName ?? "默认")",
            for: updatedProject.id
        )

        guard wasRunning else {
            return .success(())
        }

        let stopResult = await stopServer(for: updatedProject, cleanCache: false)
        guard case .success = stopResult else {
            appendSystemTerminalMessage("启动模式切换已保存，但停止旧进程失败", for: updatedProject.id)
            return stopResult
        }

        return startServer(for: projects[index])
    }

    @MainActor
    func startServer(for project: Project) -> Result<Void, ProjectServiceError> {
        let category = getCategoryName(for: project.type)
        switch project.type {
        case .devServer:
            return startProjectThroughCoordinator(for: project, category: category)
        case .miniApp:
            return startProjectThroughCoordinator(for: project, category: category)
        }
    }

    @MainActor
    func stopServer(for project: Project, cleanCache: Bool = true) async -> Result<Void, ProjectServiceError> {
        let category = getCategoryName(for: project.type)
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].transitionState = .stopping
        }
        switch project.type {
        case .devServer: return await stopDevServerWithoutOutput(for: project, category: category, cleanCache: cleanCache)
        case .miniApp: return await stopDevServerWithOutput(for: project, category: category)
        }
    }

    @MainActor
    private func startProjectThroughCoordinator(
        for project: Project,
        category: String
    ) -> Result<Void, ProjectServiceError> {
        let plan = ProjectStartupCoordinator.makePlan(
            for: project,
            fallbackCleanCommand: cleanCommand(for: project)
        )
        applyInitialStartupState(for: project.id, shouldInstallDependencies: plan.shouldInstallDependencies)

        return processManager.startProject(
            for: project,
            category: category,
            plan: plan,
            onStart: { [weak self] pid in
                Self.performStartupUpdate(on: self) { service in
                    service.handleProjectProcessStart(for: project, pid: pid)
                }
            },
            onEvent: { [weak self] event in
                Self.performStartupUpdate(on: self) { service in
                    service.handleProjectStartupEvent(event, for: project)
                }
            },
            onCompletion: { [weak self] completion in
                Self.performStartupUpdate(on: self) { service in
                    service.handleProjectStartupCompletion(completion, for: project.id)
                }
            }
        ) { [weak self] projectID, output in
            Self.performStartupUpdate(on: self) { service in
                service.appendTerminalOutput(output, for: projectID)
                if ProjectStartupCoordinator.containsStartPhaseMessage(output) {
                    service.handleProjectStartupEvent(.phaseStarted(.start), for: project)
                }
            }
        }
    }

    private nonisolated static func performStartupUpdate(
        on service: ProjectService?,
        _ update: @escaping @MainActor (ProjectService) -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                guard let service else { return }
                update(service)
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard let service else { return }
                update(service)
            }
        }
    }

    @MainActor
    private func stopDevServerWithoutOutput(for project: Project, category: String, cleanCache: Bool) async -> Result<Void, ProjectServiceError> {
        appendSystemTerminalMessage("正在停止开发服务...", for: project.id)

        let result: Result<Void, ProjectServiceError>
        if let pid = project.runningProcessPID {
            result = await processService.stopProcess(pid: pid)
        } else {
            result = await processService.killProcessByPath(project.path)
        }
        
        if case .success = result {
            appendSystemTerminalMessage("开发服务已停止", for: project.id)
            await closeManagedBrowserInstances(for: project, category: category)
            if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                self.projects[idx].runningProcessPID = nil
                self.projects[idx].isRunning = false
                self.projects[idx].transitionState = .idle
            }
            NotificationCenter.default.post(name: .devServerStopped, object: nil, userInfo: ["path": project.path])
            if cleanCache { cleanCacheAfterStop(for: project) }
        } else if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
            self.projects[idx].transitionState = .idle
            if case .failure(let error) = result {
                appendSystemTerminalMessage("开发服务停止失败: \(error.localizedDescription)", for: project.id)
            }
        }
        return result
    }

    @MainActor
    private func closeManagedBrowserInstances(for project: Project, category: String) async {
        do {
            let managedBrowserInstanceService = self.managedBrowserInstanceService
            let result = try await Task.detached(priority: .utility) {
                try await managedBrowserInstanceService.terminateManagedInstances(forProjectPath: project.path)
            }.value

            if result.matchedCount > 0 {
                appendSystemTerminalMessage("检测到 \(result.matchedCount) 个受管浏览器实例", for: project.id)
                logService.info(
                    "停止项目时回收 \(result.matchedCount) 个受管浏览器实例",
                    category: category
                )
            }

            if result.terminatedPIDs.isEmpty == false {
                appendSystemTerminalMessage(
                    "已关闭浏览器实例 PID: \(result.terminatedPIDs.map(String.init).joined(separator: ", "))",
                    for: project.id
                )
                logService.success(
                    "已关闭浏览器实例 PID: \(result.terminatedPIDs.map(String.init).joined(separator: ", "))",
                    category: category
                )
            }

            if result.failedPIDs.isEmpty == false {
                appendSystemTerminalMessage(
                    "以下浏览器实例未能关闭: \(result.failedPIDs.map(String.init).joined(separator: ", "))",
                    for: project.id
                )
                logService.warning(
                    "以下浏览器实例未能关闭: \(result.failedPIDs.map(String.init).joined(separator: ", "))",
                    category: category
                )
            }
        } catch {
            appendSystemTerminalMessage("回收受管浏览器实例失败: \(error.localizedDescription)", for: project.id)
            logService.warning(
                "回收受管浏览器实例失败: \(error.localizedDescription)",
                category: category
            )
        }

        NotificationCenter.default.post(name: .browserInstancesChanged, object: nil, userInfo: ["projectPath": project.path])
    }

    @MainActor
    private func stopDevServerWithOutput(for project: Project, category: String) async -> Result<Void, ProjectServiceError> {
        let cleanCommand = cleanCommand(for: project)
        let result = await processManager.stopDevServer(for: project, category: category, cleanCommand: cleanCommand) { [weak self] pid, output in 
            Task { @MainActor [weak self] in 
                guard let self = self else { return }
                if let idx = self.projects.firstIndex(where: { $0.id == pid }) { 
                    self.projects[idx].terminalOutput += output 
                } 
            } 
        }
        if case .success = result {
            if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                self.projects[idx].runningProcessPID = nil
                self.projects[idx].isRunning = false
                self.projects[idx].transitionState = .idle
            }
        } else if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
            self.projects[idx].transitionState = .idle
        }
        return result
    }

    @MainActor
    private func applyInitialStartupState(for projectID: UUID, shouldInstallDependencies: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        devServerDetectionTriggeredProjectIDs.remove(projectID)
        projects[index].transitionState = shouldInstallDependencies ? .installing : .starting
    }

    @MainActor
    private func handleProjectProcessStart(
        for project: Project,
        pid: Int32
    ) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }

        projects[index].runningProcessPID = pid
        projects[index].isRunning = true
    }

    @MainActor
    private func handleProjectStartupEvent(_ event: ProjectStartupEvent, for project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }

        switch event {
        case .phaseStarted(.install):
            projects[index].transitionState = .installing
        case .phaseStarted(.clean):
            break
        case .phaseStarted(.start):
            switch project.type {
            case .devServer:
                projects[index].transitionState = .starting
            case .miniApp:
                projects[index].transitionState = .idle
            }
        case .startCommandStarted(let pid):
            projects[index].runningProcessPID = pid
            projects[index].isRunning = true
            postDevServerDetectionIfNeeded(for: project.id, path: project.path, pid: pid)
        }
    }

    @MainActor
    private func postDevServerDetectionIfNeeded(for projectID: UUID, path: String, pid: Int32) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard projects[index].type == .devServer else { return }
        guard devServerDetectionTriggeredProjectIDs.contains(projectID) == false else { return }

        devServerDetectionTriggeredProjectIDs.insert(projectID)
        NotificationCenter.default.post(
            name: .devServerProcessStarted,
            object: nil,
            userInfo: ["pid": pid, "path": path]
        )
    }

    @MainActor
    private func clearDevServerDetectionTrigger(for projectID: UUID) {
        devServerDetectionTriggeredProjectIDs.remove(projectID)
    }

    @MainActor
    private func resetProjectStartupState(at index: Int) {
        let projectID = projects[index].id
        clearDevServerDetectionTrigger(for: projectID)
        projects[index].runningProcessPID = nil
        projects[index].isRunning = false
        projects[index].transitionState = .idle
    }

    @MainActor
    private func appendTerminalOutput(_ output: String, for projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }

        projects[index].terminalOutput += output
        projects[index].terminalOutput = terminalHandler.limitOutput(projects[index].terminalOutput)
    }

    @MainActor
    private func appendSystemTerminalMessage(_ message: String, for projectID: UUID) {
        appendTerminalOutput("[系统] \(message)\n", for: projectID)
    }

    @MainActor
    private func handleProjectStartupCompletion(_ completion: ProjectStartupCompletion, for projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }

        switch completion {
        case .exited(let exitCode):
            if exitCode != 0 || projects[index].transitionState != .idle {
                resetProjectStartupState(at: index)
            } else {
                clearDevServerDetectionTrigger(for: projectID)
            }
        case .executionFailed:
            resetProjectStartupState(at: index)
        }
    }

    @MainActor
    func reconcileDetectedDevServers(_ servers: [DevServer]) {
        let normalizedServers = servers.map { server in
            (server: server, normalizedPath: normalizedPath(for: server.projectPath))
        }

        for index in projects.indices where projects[index].type == .devServer {
            let projectPath = normalizedPath(for: projects[index].path)
            let matchedServer = normalizedServers.first { $0.normalizedPath == projectPath }?.server

            if let matchedServer {
                projects[index].runningProcessPID = matchedServer.id
                projects[index].isRunning = true

                if projects[index].transitionState == .starting {
                    projects[index].transitionState = .idle
                }
                clearDevServerDetectionTrigger(for: projects[index].id)
            } else if projects[index].transitionState == .stopping {
                projects[index].runningProcessPID = nil
                projects[index].isRunning = false
                projects[index].transitionState = .idle
                clearDevServerDetectionTrigger(for: projects[index].id)
            }
        }
    }

    @MainActor
    private func cleanCacheAfterStop(for project: Project) {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let cmd = cleanCommand(for: project)
            if cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                await MainActor.run {
                    self.appendSystemTerminalMessage("正在执行缓存清理...", for: project.id)
                }
            }

            let result = GitService.shared.cleanCache(at: project.path, command: cmd)

            await MainActor.run {
                switch result {
                case .success:
                    if cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        self.appendSystemTerminalMessage("缓存清理完成", for: project.id)
                    }
                case .failure(let error):
                    self.appendSystemTerminalMessage("缓存清理失败: \(error.localizedDescription)", for: project.id)
                }
            }
        }
    }

    @MainActor
    private func getProcessKeywords() -> [String] {
        var kw = AppConfig.Process.processKeywords
        if projects.contains(where: { $0.type == .miniApp }) { kw.append("uni") }
        return kw
    }

    private func getCategoryName(for type: ProjectType) -> String { return type == .devServer ? "开发项目" : "小程序" }

    @MainActor
    private func loadProjects() {
        let loadedProjects = persistenceService.load()
        applyPersistenceMigration(projects: loadedProjects)
        synchronizeMonitorsWithProjects()
        refreshAll()
    }

    @MainActor
    private func saveProjects() { _ = persistenceService.save(projects) }

    @MainActor
    private func applyPersistenceMigration(projects: [Project]) {
        let result = ProjectPersistenceMigration.migrate(
            projects: projects,
            commandConfigs: commandConfigService.configs
        )
        self.projects = result.projects
        commandConfigService.applyPersistenceMigration(result.commandConfigs)
        if result.didChange {
            saveProjects()
        }
    }

    private func normalizedPath(for path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func cleanCommand(for project: Project) -> String {
        let trimmedCommand = project.cleanCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCommand.isEmpty ? AppConfig.Git.cacheCleanCommand : trimmedCommand
    }
}
