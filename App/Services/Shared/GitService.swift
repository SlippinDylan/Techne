//
//  GitService.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation
import SwiftGitX

/// Git 操作服务
/// 提供统一的 Git 操作接口，被 DevProjectService 和 MiniAppService 共享使用
final class GitService: Sendable {
    nonisolated static let shared = GitService()

    nonisolated private init() {}

    // MARK: - Public Methods

    /// 获取当前分支
    /// - Parameter path: 项目路径
    /// - Returns: 当前分支名称，失败返回 nil
    nonisolated func getCurrentBranch(at path: String) -> String? {
        do {
            let repository = try Repository.open(at: URL(fileURLWithPath: path))
            return try repository.branch.current.name
        } catch {
            return detachedHEADDescription(at: path)
        }
    }

    /// 获取本地分支列表
    /// - Parameter path: 项目路径
    /// - Returns: 分支名称数组
    nonisolated func getLocalBranches(at path: String) -> [String] {
        do {
            let repository = try Repository.open(at: URL(fileURLWithPath: path))
            return try repository.branch.list(.local).map(\.name)
        } catch {
            // 无法在 nonisolated 方法中调用 LogService，使用 print 记录错误
            print("⚠️ [GitService] 获取本地分支失败: \(error.localizedDescription)")
        }

        return []
    }

    /// 获取工作目录状态
    /// - Parameter path: 项目路径
    /// - Returns: (文件数量, 是否有更改)
    nonisolated func getWorkingDirectoryStatus(at path: String) -> (fileCount: Int, hasChanges: Bool) {
        do {
            let repository = try Repository.open(at: URL(fileURLWithPath: path))
            let entries = try repository.status()
            return (fileCount: entries.count, hasChanges: !entries.isEmpty)
        } catch {
            // 无法在 nonisolated 方法中调用 LogService，使用 print 记录错误
            print("⚠️ [GitService] 获取工作目录状态失败: \(error.localizedDescription)")
        }

        return (fileCount: 0, hasChanges: false)
    }

    /// 放弃工作目录的所有更改
    /// - Parameter path: 项目路径
    /// - Returns: 操作结果
    nonisolated func discardChanges(at path: String) -> Result<Void, ProjectServiceError> {
        // 先恢复已跟踪文件的更改
        let restoreResult = executeGitCommand(
            at: path,
            arguments: ["restore", "."],
            operation: AppLocalized("operation.git.restore_changes")
        )

        // 清理未跟踪的文件
        let cleanResult = executeGitCommand(
            at: path,
            arguments: ["clean", "-fd"],
            operation: AppLocalized("operation.git.clean_untracked_files")
        )

        // 检查两个操作的结果
        switch (restoreResult, cleanResult) {
        case (.success, .success):
            return .success(())
        case (.failure(let error), _):
            // restore 失败，返回 restore 的错误
            return .failure(error)
        case (_, .failure(let error)):
            // restore 成功但 clean 失败，返回 clean 的错误
            return .failure(error)
        }
    }

    /// 切换分支
    /// - Parameters:
    ///   - path: 项目路径
    ///   - branch: 目标分支名称
    /// - Returns: 操作结果
    nonisolated func switchBranch(at path: String, to branch: String) -> Result<Void, ProjectServiceError> {
        do {
            let repository = try Repository.open(at: URL(fileURLWithPath: path))
            let targetBranch = try repository.branch.get(named: branch, type: .local)
            try repository.switch(to: targetBranch)
            return .success(())
        } catch {
            return .failure(.gitOperationFailed(operation: AppLocalizedFormat("operation.git.switch_to_branch", branch), reason: error.localizedDescription))
        }
    }

    /// 清理缓存
    /// - Parameters:
    ///   - path: 项目路径
    ///   - command: 清理命令
    /// - Returns: 操作结果
    nonisolated func cleanCache(at path: String, command: String) -> Result<Void, ProjectServiceError> {
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)

        // 如果命令为空，直接返回成功（不需要清理）
        guard !trimmedCommand.isEmpty else {
            return .success(())
        }

        // 验证命令安全性：使用基于模式的验证
        guard isCleanCommandSafe(trimmedCommand) else {
            return .failure(.gitOperationFailed(
                operation: AppLocalized("operation.git.clean_cache"),
                reason: AppLocalizedFormat("error.git.command_not_allowed", command)
            ))
        }

        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: path)
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", trimmedCommand]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "GitService")

            if terminationStatus == 0 {
                return .success(())
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let error = String(data: errorData, encoding: .utf8) ?? AppLocalized("error.git.clean_cache_failed")
                // 不在这里记录日志，由调用方负责
                return .failure(.gitOperationFailed(operation: AppLocalized("operation.git.clean_cache"), reason: error))
            }
        } catch {
            // 不在这里记录日志，由调用方负责
            return .failure(.gitOperationFailed(operation: AppLocalized("operation.git.clean_cache"), reason: error.localizedDescription))
        }
    }

    /// 验证清理命令的安全性
    /// - Parameter command: 要验证的命令
    /// - Returns: 命令是否安全
    nonisolated private func isCleanCommandSafe(_ command: String) -> Bool {
        // 危险字符和模式检查
        let dangerousPatterns = [
            "|",      // 管道
            ";",      // 命令分隔符
            "&",      // 后台执行
            "$(",     // 命令替换
            "`",      // 命令替换
            ">",      // 重定向
            "<",      // 重定向
            "~",      // 家目录（防止删除家目录）
            "..",     // 上级目录（防止删除父目录）
            "sudo",   // 提权
            "chmod",  // 修改权限
            "chown",  // 修改所有者
        ]

        // 检查是否包含危险模式
        for pattern in dangerousPatterns {
            if command.contains(pattern) {
                return false
            }
        }

        // 只允许 rm 命令，且必须有 -rf 参数
        guard command.hasPrefix("rm -rf ") || command.hasPrefix("rm -fr ") else {
            return false
        }

        // 提取要删除的路径
        let pathPart = command.replacingOccurrences(of: "rm -rf ", with: "")
            .replacingOccurrences(of: "rm -fr ", with: "")
            .trimmingCharacters(in: .whitespaces)

        // 路径不能为空
        guard !pathPart.isEmpty else {
            return false
        }

        // 分割多个路径（用空格分隔）
        let paths = pathPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // 验证每个路径
        for path in paths {
            // 路径必须是相对路径（不能以 / 开头）
            guard !path.hasPrefix("/") else {
                return false
            }

            // 路径不能包含危险字符
            guard !path.contains("*") && !path.contains("?") else {
                return false
            }

            // 路径必须是常见的构建输出目录
            let allowedDirectories = [
                "dist",
                "build",
                ".next",
                "node_modules/.cache",
                ".cache",
                "out",
                "target",
                ".turbo",
                ".nuxt",
                ".output",
                "coverage",
                ".vite",
                ".parcel-cache"
            ]

            guard allowedDirectories.contains(path) else {
                return false
            }
        }

        return true
    }

    // MARK: - Private Helper Methods

    /// 执行 Git 命令的通用方法
    nonisolated private func executeGitCommand(
        at path: String,
        arguments: [String],
        operation: String
    ) -> Result<Void, ProjectServiceError> {
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: path)
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "GitService")

            if terminationStatus == 0 {
                return .success(())
            } else {
                // 读取错误输出
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? AppLocalized("error.unknown")

                // 不在这里记录日志，由调用方负责
                return .failure(.gitOperationFailed(operation: operation, reason: errorMessage))
            }
        } catch {
            // 不在这里记录日志，由调用方负责
            return .failure(.gitOperationFailed(operation: operation, reason: error.localizedDescription))
        }
    }

    nonisolated private func detachedHEADDescription(at path: String) -> String? {
        let headURL = URL(fileURLWithPath: path).appendingPathComponent(".git/HEAD")
        guard let headContent = try? String(contentsOf: headURL, encoding: .utf8) else {
            return nil
        }

        let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard !trimmed.hasPrefix("ref: refs/heads/") else {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }

        let shortSHA = String(trimmed.prefix(7))
        return shortSHA.isEmpty ? "(detached HEAD)" : shortSHA
    }

}
