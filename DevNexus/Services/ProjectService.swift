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

    private var gitMonitors: [String: GitWorkspaceMonitor] = [:]
    private var cachedProcessKeywords: [String]?

    // MARK: - Initialization

    @MainActor
    init(commandConfigService: CommandConfigService) {
        self.commandConfigService = commandConfigService
        persistenceService = PersistenceService(filename: "projects.json")
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
        if projects.contains(where: { $0.path == path }) {
            return .failure(.projectAlreadyExists(path))
        }
        let projectName = URL(fileURLWithPath: path).lastPathComponent
        let startCommand = (configId != nil ? commandConfigService.getConfig(by: configId!)?.startCommand : nil) ?? type.defaultStartCommand
        let project = Project(name: projectName, path: path, type: type, startCommand: startCommand, commandConfigId: configId)
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

    // MARK: - Monitor Management

    private func setupMonitorsForAllProjects() {
        Task { @MainActor in
            for project in projects {
                await setupMonitor(for: project)
            }
        }
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
        let cleanCommand = getCommandConfig(for: project)?.cleanCommand ?? AppConfig.Git.cacheCleanCommand
        
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
    func startServer(for project: Project) -> Result<Void, ProjectServiceError> {
        let category = getCategoryName(for: project.type)
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].transitionState = .starting
        }
        switch project.type {
        case .devServer: return startDevServerWithoutOutput(for: project, category: category)
        case .miniApp: return startDevServerWithOutput(for: project, category: category)
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
    private func startDevServerWithoutOutput(for project: Project, category: String) -> Result<Void, ProjectServiceError> {
        let cleanCommand = getCommandConfig(for: project)?.cleanCommand ?? AppConfig.Git.cacheCleanCommand
        let escapedPath = ShellEscape.escape(project.path)
        let command = "source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || source ~/.bashrc 2>/dev/null\ncd \(escapedPath)\n\(cleanCommand)\n\(project.startCommand)"
        Task {
            do {
                _ = try await ModernProcessExecutor.execute(
                    command: command,
                    in: URL(fileURLWithPath: project.path),
                    onStart: { [weak self] pid in
                        Task { @MainActor [weak self] in
                            if let idx = self?.projects.firstIndex(where: { $0.id == project.id }) {
                                self?.projects[idx].runningProcessPID = pid
                                self?.projects[idx].isRunning = true
                            }
                            NotificationCenter.default.post(
                                name: .devServerProcessStarted,
                                object: nil,
                                userInfo: ["pid": pid, "path": project.path]
                            )
                        }
                    },
                    onOutput: { output in
                        let cleanOutput = self.terminalHandler.stripANSICodes(output)
                        let keywords = ["error", "warn", "failed", "✓", "✗", "listening", "ready", "started"]
                        let lowercased = cleanOutput.lowercased()
                        let shouldLog = keywords.contains { lowercased.contains($0) }
                        let logMessage = String(cleanOutput.prefix(500))
                        Task { @MainActor [weak self] in
                            if shouldLog {
                                LogService.shared.info(logMessage, category: project.name)
                            }
                            if let idx = self?.projects.firstIndex(where: { $0.id == project.id }) {
                                self?.projects[idx].terminalOutput += output
                                if let terminalOutput = self?.projects[idx].terminalOutput {
                                    self?.projects[idx].terminalOutput = self?.terminalHandler.limitOutput(terminalOutput) ?? terminalOutput
                                }
                            }
                        }
                    }
                )
            } catch {
                await MainActor.run { [weak self] in
                    if let idx = self?.projects.firstIndex(where: { $0.id == project.id }) {
                        self?.projects[idx].transitionState = .idle
                        self?.projects[idx].isRunning = false
                        self?.projects[idx].runningProcessPID = nil
                    }
                }
                AppLogError("执行异常：\(error.localizedDescription)", category: category)
            }
        }
        return .success(())
    }

    @MainActor
    private func stopDevServerWithoutOutput(for project: Project, category: String, cleanCache: Bool) async -> Result<Void, ProjectServiceError> {
        let result: Result<Void, ProjectServiceError>
        if let pid = project.runningProcessPID {
            result = await processService.stopProcess(pid: pid)
        } else {
            result = await processService.killProcessByPath(project.path)
        }
        
        if case .success = result {
            if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                self.projects[idx].runningProcessPID = nil
                self.projects[idx].isRunning = false
                self.projects[idx].transitionState = .idle
            }
            NotificationCenter.default.post(name: .devServerStopped, object: nil, userInfo: ["path": project.path])
            if cleanCache { cleanCacheAfterStop(for: project) }
        } else if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
            self.projects[idx].transitionState = .idle
        }
        return result
    }

    @MainActor
    private func startDevServerWithOutput(for project: Project, category: String) -> Result<Void, ProjectServiceError> {
        let cleanCommand = getCommandConfig(for: project)?.cleanCommand ?? AppConfig.Git.cacheCleanCommand
        return processManager.startDevServer(for: project, category: category, cleanCommand: cleanCommand, onStart: { [weak self] pid in
            Task { @MainActor [weak self] in
                if let idx = self?.projects.firstIndex(where: { $0.id == project.id }) {
                    self?.projects[idx].runningProcessPID = pid
                    self?.projects[idx].isRunning = true
                    self?.projects[idx].transitionState = .idle
                }
            }
        }) { [weak self] pid, output in 
            Task { @MainActor [weak self] in 
                guard let self = self else { return }
                if let idx = self.projects.firstIndex(where: { $0.id == pid }) { 
                    self.projects[idx].terminalOutput += output
                    self.projects[idx].terminalOutput = self.terminalHandler.limitOutput(self.projects[idx].terminalOutput) 
                } 
            } 
        }
    }

    @MainActor
    private func stopDevServerWithOutput(for project: Project, category: String) async -> Result<Void, ProjectServiceError> {
        let cleanCommand = getCommandConfig(for: project)?.cleanCommand ?? AppConfig.Git.cacheCleanCommand
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
            } else if projects[index].transitionState == .stopping {
                projects[index].runningProcessPID = nil
                projects[index].isRunning = false
                projects[index].transitionState = .idle
            }
        }
    }

    private func getCommandConfig(for project: Project) -> CommandConfig? {
        guard let id = project.commandConfigId else { return nil }
        return commandConfigService.getConfig(by: id)
    }

    @MainActor
    private func cleanCacheAfterStop(for project: Project) {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let cmd = getCommandConfig(for: project)?.cleanCommand ?? AppConfig.Git.cacheCleanCommand
            _ = GitService.shared.cleanCache(at: project.path, command: cmd)
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
        projects = persistenceService.load()
        setupMonitorsForAllProjects()
        refreshAll()
    }

    @MainActor
    private func saveProjects() { _ = persistenceService.save(projects) }

    private func normalizedPath(for path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
