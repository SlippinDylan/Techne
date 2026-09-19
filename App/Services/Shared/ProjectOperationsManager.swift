//
//  ProjectOperationsManager.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 项目操作管理器
/// 提供所有项目类型共享的操作逻辑
@MainActor
class ProjectOperationsManager {
    // MARK: - Status Refresh

    /// 刷新所有项目的工作目录状态和当前分支
    nonisolated func refreshWorkingDirectoryStatus(projects: [Project]) async -> [Project] {
        await withTaskGroup(of: (Int, Int, String?).self) { group in
            var updatedProjects = projects

            for (index, project) in projects.enumerated() {
                let projectPath = project.path
                group.addTask {
                    let status = GitService.shared.getWorkingDirectoryStatus(at: projectPath)
                    let currentBranch = GitService.shared.getCurrentBranch(at: projectPath)
                    return (index, status.fileCount, currentBranch)
                }
            }

            for await (index, fileCount, currentBranch) in group {
                updatedProjects[index].uncommittedFileCount = fileCount
                if let branch = currentBranch {
                    updatedProjects[index].currentBranch = branch
                }
            }

            return updatedProjects
        }
    }

    // MARK: - Git Operations

    /// 放弃工作目录更改
    func discardChanges(
        at path: String,
        projectName: String,
        category: String
    ) -> Result<Void, ProjectServiceError> {
        // 使用全局辅助函数，彻底解决隔离冲突
        AppLogInfo(AppLocalizedFormat("log.git.discarding_changes", projectName), category: category)

        let result = GitService.shared.discardChanges(at: path)

        switch result {
        case .success:
            AppLogSuccess(AppLocalizedFormat("log.git.discarded_changes", projectName), category: category)
        case .failure(let error):
            AppLogError(AppLocalizedFormat("log.git.discard_changes_failed", projectName, error.localizedDescription), category: category)
        }

        return result
    }

    /// 切换分支 (异步化修复版)
    func switchBranch(
        at path: String,
        to branch: String,
        projectName: String,
        category: String,
        cleanCommand: String,
        stopProcess: () async -> Result<Void, ProjectServiceError>,
        startProcess: () -> Result<Void, ProjectServiceError>,
        autoStart: Bool,
        onStatusUpdate: ((Int) -> Void)? = nil
    ) async -> Result<Void, ProjectServiceError> {
        AppLogInfo(AppLocalizedFormat("log.git.switching_branch", projectName, branch), category: category)

        // 1. 在后台线程检查工作区状态
        let workingDirStatus = await Task.detached(priority: .userInitiated) {
            GitService.shared.getWorkingDirectoryStatus(at: path)
        }.value

        if workingDirStatus.hasChanges {
            let errorMsg = AppLocalizedFormat("error.git.uncommitted_files", Int64(workingDirStatus.fileCount))
            AppLogError(AppLocalizedFormat("log.git.branch_switch_blocked", projectName, errorMsg), category: category)
            onStatusUpdate?(workingDirStatus.fileCount)
            return .failure(.gitOperationFailed(operation: AppLocalized("operation.git.switch_branch"), reason: errorMsg))
        }

        // 2. 停止进程 (本身已是异步方法)
        let stopResult = await stopProcess()
        if case .failure(let error) = stopResult {
            AppLogWarning(AppLocalizedFormat("log.process.stop_warning", error.localizedDescription), category: category)
        }

        try? await Task.sleep(nanoseconds: UInt64(AppConfig.Process.startupDelay * 1_000_000_000))

        // 3. 在后台线程执行前置清理
        let cleanResultBefore = await Task.detached(priority: .userInitiated) {
            GitService.shared.cleanCache(at: path, command: cleanCommand)
        }.value
        
        if case .failure(let error) = cleanResultBefore {
            AppLogError(AppLocalizedFormat("log.git.pre_cleanup_failed", projectName, error.localizedDescription), category: category)
            return .failure(error)
        }

        // 4. 在后台线程执行分支切换 (git checkout)
        let switchResult = await Task.detached(priority: .userInitiated) {
            GitService.shared.switchBranch(at: path, to: branch)
        }.value
        
        if case .failure(let error) = switchResult {
            AppLogError(AppLocalizedFormat("log.git.switch_failed", projectName, error.localizedDescription), category: category)
            return .failure(error)
        }

        // 5. 在后台线程执行后置清理
        let cleanResultAfter = await Task.detached(priority: .userInitiated) {
            GitService.shared.cleanCache(at: path, command: cleanCommand)
        }.value
        
        if case .failure(let error) = cleanResultAfter {
            AppLogError(AppLocalizedFormat("log.git.post_cleanup_failed", projectName, error.localizedDescription), category: category)
            return .failure(error)
        }

        AppLogSuccess(AppLocalizedFormat("log.git.branch_switch_completed", projectName, branch), category: category)

        if autoStart {
            if case .failure(let error) = startProcess() {
                return .failure(error)
            }
        }

        return .success(())
    }
}
