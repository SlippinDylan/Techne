//
//  ProjectService.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation
import Observation

enum ProjectServiceStartupBehavior: Sendable {
    case restoreAndRefresh
    case restoreWithoutRefresh
    case empty
}

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

    private let processService: ProcessService
    private let persistenceService: PersistenceService<Project>
    private let logService = LogService.shared
    private let operationsManager = ProjectOperationsManager()
    private let processManager: ProcessManager
    private let terminalHandler = TerminalOutputHandler()
    private let commandConfigService: CommandConfigService
    private let weChatDevToolsService: WeChatDevToolsService

    private var gitMonitors: [String: GitWorkspaceMonitor] = [:]
    private var cachedProcessKeywords: [String]?
    private var devServerDetectionTriggeredProjectIDs: Set<UUID> = []
    @MainActor private var activeRunIDs: [UUID: UUID] = [:]

    // MARK: - Initialization

    @MainActor
    init(
        commandConfigService: CommandConfigService,
        processService: ProcessService = .shared,
        weChatDevToolsService: WeChatDevToolsService = WeChatDevToolsService(),
        persistenceService: PersistenceService<Project> = PersistenceService(filename: "projects.json"),
        startupBehavior: ProjectServiceStartupBehavior = .restoreAndRefresh
    ) {
        self.commandConfigService = commandConfigService
        self.processService = processService
        self.processManager = ProcessManager(processService: processService)
        self.weChatDevToolsService = weChatDevToolsService
        self.persistenceService = persistenceService
        applyStartupBehavior(startupBehavior)
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
                    for refreshedProject in updated {
                        guard let index = self.projects.firstIndex(where: { $0.id == refreshedProject.id }) else {
                            continue
                        }
                        self.projects[index].currentBranch = refreshedProject.currentBranch
                        self.projects[index].uncommittedFileCount = refreshedProject.uncommittedFileCount
                        if self.projects[index].transitionState == .idle,
                           self.projects[index].runtimeKind != .weChatNative {
                            self.projects[index].isRunning = refreshedProject.isRunning
                        }
                    }
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
                        if self.projects[index].runtimeKind != .weChatNative {
                            self.projects[index].isRunning = status.isRunning
                        }
                    }
                }
            }
        }
    }

    // MARK: - Project Management (@MainActor)

    @MainActor
    func addProject(path: String, type: ProjectType, configId: UUID? = nil) -> Result<Project, ProjectServiceError> {
        let canonicalPath = ProjectPath.canonical(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.pathNotFound(canonicalPath))
        }
        if ProjectPersistenceMigration.isTemporaryProjectPath(canonicalPath) {
            return .failure(.invalidConfiguration(AppLocalized("error.project.temporary_directory")))
        }
        if projects.contains(where: { ProjectPath.canonical($0.path) == canonicalPath }) {
            return .failure(.projectAlreadyExists(canonicalPath))
        }
        let projectName = URL(fileURLWithPath: canonicalPath).lastPathComponent
        let project: Project
        if let configId {
            guard let commandConfig = commandConfigService.getConfig(by: configId) else {
                return .failure(.invalidConfiguration(AppLocalized("error.project.selected_command_configuration_not_found")))
            }
            project = ProjectCommandSnapshotResolver.makeProject(
                name: projectName,
                path: canonicalPath,
                type: type,
                commandConfigId: configId,
                legacyConfig: commandConfig
            )
        } else {
            switch ProjectCommandSnapshotResolver.analyzedSnapshot(for: type, path: canonicalPath) {
            case .success(let snapshot):
                project = ProjectCommandSnapshotResolver.makeProject(
                    name: projectName,
                    path: canonicalPath,
                    type: type,
                    snapshot: snapshot
                )
            case .failure(let error):
                return .failure(.invalidConfiguration(error.localizedDescription))
            }
        }
        projects.append(project)
        saveProjects()
        
        Task {
            await setupMonitor(for: project)
            refreshProjectStatusAsync(at: canonicalPath)
        }
        return .success(project)
    }

    @MainActor
    func removeProject(_ project: Project) {
        let path = project.path
        processManager.cancelManagedExecution(for: project.id)
        activeRunIDs[project.id] = nil
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
            return .failure(.invalidConfiguration(AppLocalized("error.project.invalid_startup_mode")))
        }

        let wasRunning = projects[index].isRunning || projects[index].runningProcessPID != nil
        projects[index].selectStartupMode(id: modeID)
        let updatedProject = projects[index]
        saveProjects()
        appendSystemTerminalMessage(
            AppLocalizedFormat("terminal.project.startup_mode_changed", updatedProject.selectedStartupMode?.displayName ?? AppLocalized("startup_mode.default")),
            for: updatedProject.id
        )

        guard wasRunning else {
            return .success(())
        }

        let stopResult = await stopServer(for: updatedProject)
        guard case .success = stopResult else {
            appendSystemTerminalMessage(AppLocalized("terminal.project.startup_mode_changed_stop_failed"), for: updatedProject.id)
            return stopResult
        }

        return startServer(for: projects[index])
    }

    @MainActor
    func startServer(for project: Project) -> Result<Void, ProjectServiceError> {
        if project.runtimeKind == .weChatNative {
            return openNativeMiniApp(project)
        }
        let category = getCategoryName(for: project.type)
        switch project.type {
        case .devServer:
            return startProjectThroughCoordinator(for: project, category: category)
        case .miniApp:
            return startProjectThroughCoordinator(for: project, category: category)
        }
    }

    @MainActor
    func stopServer(for project: Project) async -> Result<Void, ProjectServiceError> {
        if project.runtimeKind == .weChatNative {
            return await closeNativeMiniApp(project)
        }
        let category = getCategoryName(for: project.type)
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].transitionState = .stopping
        }
        switch project.type {
        case .devServer: return await stopDevServerWithoutOutput(for: project)
        case .miniApp: return await stopDevServerWithOutput(for: project, category: category)
        }
    }

    @MainActor
    func restartServer(for project: Project) async -> Result<Void, ProjectServiceError> {
        let stopResult = await stopServer(for: project)
        guard case .success = stopResult else {
            return stopResult
        }
        guard let currentProject = projects.first(where: { $0.id == project.id }) else {
            return .failure(.pathNotFound(project.path))
        }
        appendSystemTerminalMessage(AppLocalized("terminal.project.restarting"), for: project.id)
        return startServer(for: currentProject)
    }

    @MainActor
    func resetMiniAppFileWatching(for project: Project) async -> Result<Void, ProjectServiceError> {
        guard project.type == .miniApp else {
            return .failure(.invalidConfiguration(AppLocalized("error.project.file_watching_requires_mini_program")))
        }

        appendSystemTerminalMessage(AppLocalized("terminal.wechat.rebuilding_file_watching"), for: project.id)
        let result = await weChatDevToolsService.resetFileWatching(for: project.path)
        switch result {
        case .success(let output):
            if output.isEmpty == false {
                appendTerminalOutput("\(output)\n", for: project.id)
            }
            appendSystemTerminalMessage(AppLocalized("terminal.wechat.file_watching_rebuilt"), for: project.id)
            return .success(())
        case .failure(let error):
            appendSystemTerminalMessage(AppLocalizedFormat("terminal.wechat.file_watching_rebuild_failed", error.localizedDescription), for: project.id)
            return .failure(.processStartFailed(error.localizedDescription))
        }
    }

    @MainActor
    private func openNativeMiniApp(_ project: Project) -> Result<Void, ProjectServiceError> {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return .failure(.pathNotFound(project.path))
        }
        projects[index].transitionState = .starting
        appendSystemTerminalMessage(AppLocalized("terminal.wechat.opening_native_mini_program"), for: project.id)

        Task { @MainActor in
            let result = await weChatDevToolsService.openProject(at: project.path)
            guard let currentIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
            projects[currentIndex].transitionState = .idle
            switch result {
            case .success(let output):
                projects[currentIndex].isRunning = true
                if output.isEmpty == false {
                    appendTerminalOutput("\(output)\n", for: project.id)
                }
                appendSystemTerminalMessage(AppLocalized("terminal.wechat.project_opened"), for: project.id)
            case .failure(let error):
                projects[currentIndex].isRunning = false
                appendSystemTerminalMessage(AppLocalizedFormat("terminal.wechat.open_project_failed", error.localizedDescription), for: project.id)
            }
        }
        return .success(())
    }

    @MainActor
    private func closeNativeMiniApp(_ project: Project) async -> Result<Void, ProjectServiceError> {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return .failure(.pathNotFound(project.path))
        }
        projects[index].transitionState = .stopping
        appendSystemTerminalMessage(AppLocalized("terminal.wechat.closing_project"), for: project.id)
        let result = await weChatDevToolsService.closeProject(at: project.path)
        guard let currentIndex = projects.firstIndex(where: { $0.id == project.id }) else {
            return .failure(.pathNotFound(project.path))
        }
        projects[currentIndex].transitionState = .idle
        switch result {
        case .success(let output):
            projects[currentIndex].isRunning = false
            if output.isEmpty == false {
                appendTerminalOutput("\(output)\n", for: project.id)
            }
            appendSystemTerminalMessage(AppLocalized("terminal.wechat.project_closed"), for: project.id)
            return .success(())
        case .failure(let error):
            appendSystemTerminalMessage(AppLocalizedFormat("terminal.wechat.close_project_failed", error.localizedDescription), for: project.id)
            return .failure(.processStopFailed(error.localizedDescription))
        }
    }

    @MainActor
    private func startProjectThroughCoordinator(
        for project: Project,
        category: String
    ) -> Result<Void, ProjectServiceError> {
        let runID = UUID()
        activeRunIDs[project.id] = runID
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
                    guard service.activeRunIDs[project.id] == runID else { return }
                    service.handleProjectProcessStart(for: project, pid: pid)
                }
            },
            onEvent: { [weak self] event in
                Self.performStartupUpdate(on: self) { service in
                    guard service.activeRunIDs[project.id] == runID else { return }
                    service.handleProjectStartupEvent(
                        event,
                        for: project,
                        dependencyFingerprint: plan.dependencyFingerprint
                    )
                }
            },
            onCompletion: { [weak self] completion in
                Self.performStartupUpdate(on: self) { service in
                    guard service.activeRunIDs[project.id] == runID else { return }
                    service.handleProjectStartupCompletion(completion, for: project.id)
                    service.activeRunIDs[project.id] = nil
                }
            }
        ) { [weak self] projectID, output in
            Self.performStartupUpdate(on: self) { service in
                guard service.activeRunIDs[project.id] == runID else { return }
                service.appendTerminalOutput(output, for: projectID)
                if ProjectStartupCoordinator.containsStartPhaseMessage(output) {
                    service.handleProjectStartupEvent(
                        .phaseStarted(.start),
                        for: project,
                        dependencyFingerprint: plan.dependencyFingerprint
                    )
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
    private func stopDevServerWithoutOutput(for project: Project) async -> Result<Void, ProjectServiceError> {
        appendSystemTerminalMessage(AppLocalized("terminal.project.stopping_development_service"), for: project.id)

        let result = await processManager.stopDevServer(
            for: project,
            category: getCategoryName(for: project.type)
        ) { [weak self] projectID, output in
            Self.performStartupUpdate(on: self) { service in
                service.appendTerminalOutput(output, for: projectID)
            }
        }
        
        if case .success = result {
            appendSystemTerminalMessage(AppLocalized("terminal.project.development_service_stopped"), for: project.id)
            if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                self.projects[idx].runningProcessPID = nil
                self.projects[idx].isRunning = false
                self.projects[idx].transitionState = .idle
            }
            NotificationCenter.default.post(name: .devServerStopped, object: nil, userInfo: ["path": project.path])
        } else if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
            self.projects[idx].transitionState = .idle
            if case .failure(let error) = result {
                appendSystemTerminalMessage(AppLocalizedFormat("terminal.project.development_service_stop_failed", error.localizedDescription), for: project.id)
            }
        }
        return result
    }

    @MainActor
    private func stopDevServerWithOutput(for project: Project, category: String) async -> Result<Void, ProjectServiceError> {
        let result = await processManager.stopDevServer(for: project, category: category) { [weak self] pid, output in
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
    private func handleProjectStartupEvent(
        _ event: ProjectStartupEvent,
        for project: Project,
        dependencyFingerprint: String?
    ) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        if projects[index].transitionState == .stopping,
           event != .dependenciesInstalled {
            return
        }

        switch event {
        case .phaseStarted(.install):
            projects[index].transitionState = .installing
        case .phaseStarted(.clean):
            break
        case .phaseStarted(.start):
            if projects[index].preparedDependencyFingerprint == nil,
               let dependencyFingerprint {
                projects[index].preparedDependencyFingerprint = dependencyFingerprint
                saveProjects()
            }
            switch project.type {
            case .devServer:
                projects[index].transitionState = .starting
            case .miniApp:
                projects[index].transitionState = .idle
            }
        case .dependenciesInstalled:
            if let dependencyFingerprint,
               projects[index].preparedDependencyFingerprint != dependencyFingerprint {
                projects[index].preparedDependencyFingerprint = dependencyFingerprint
                saveProjects()
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
        appendTerminalOutput(AppLocalizedFormat("terminal.system_message", message), for: projectID)
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
        let managedProjectPaths = projects
            .filter { $0.type == .devServer }
            .map(\.path)

        for index in projects.indices where projects[index].type == .devServer {
            let normalizedProjectPath = DevServerProjectMatcher.normalize(projects[index].path)
            let pidMatchedServer = projects[index].runningProcessPID.flatMap { pid in
                servers.first { server in
                    server.id == pid
                        && DevServerProjectMatcher.bestMatchingProjectPath(
                            for: server,
                            managedProjectPaths: managedProjectPaths
                        ) == normalizedProjectPath
                }
            }
            let pathMatchedServer = servers.first { server in
                DevServerProjectMatcher.bestMatchingProjectPath(
                    for: server,
                    managedProjectPaths: managedProjectPaths
                ) == normalizedProjectPath
            }
            let matchedServer = pidMatchedServer ?? pathMatchedServer

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
    private func getProcessKeywords() -> [String] {
        var kw = AppConfig.Process.processKeywords
        if projects.contains(where: { $0.type == .miniApp }) { kw.append("uni") }
        return kw
    }

    private func getCategoryName(for type: ProjectType) -> String {
        type == .devServer ? AppLocalized("log.category.development_project") : AppLocalized("log.category.mini_program")
    }

    @MainActor
    private func applyStartupBehavior(_ startupBehavior: ProjectServiceStartupBehavior) {
        switch startupBehavior {
        case .restoreAndRefresh:
            loadProjects(shouldRefresh: true)
        case .restoreWithoutRefresh:
            loadProjects(shouldRefresh: false)
        case .empty:
            projects = []
            isLoading = false
        }
    }

    @MainActor
    private func loadProjects(shouldRefresh: Bool) {
        let loadedProjects = persistenceService.load()
        applyPersistenceMigration(projects: loadedProjects)
        synchronizeMonitorsWithProjects()
        if shouldRefresh {
            refreshAll()
        }
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

    private func cleanCommand(for project: Project) -> String {
        let trimmedCommand = project.cleanCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCommand.isEmpty ? AppConfig.Git.cacheCleanCommand : trimmedCommand
    }
}
