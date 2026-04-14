//
//  ProcessManager.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 进程管理器
/// 统一管理项目进程的启动、停止和监控
@MainActor
class ProcessManager {
    private let processService = ProcessService.shared
    private let gitService = GitService.shared
    private let logService = LogService.shared
    private let terminalHandler = TerminalOutputHandler()

    // MARK: - Process Control

    /// 启动开发服务器
    func startDevServer(
        for project: Project,
        category: String,
        cleanCommand: String,
        onStart: @escaping @Sendable (Int32) -> Void,
        onOutputUpdate: @escaping @Sendable (UUID, String) -> Void
    ) -> Result<Void, ProjectServiceError> {
        logService.info("准备启动开发服务器：\(project.name)", category: category)

        let escapedPath = ShellEscape.escape(project.path)
        let command = """
        source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || source ~/.bashrc 2>/dev/null
        cd \(escapedPath)
        \(cleanCommand.isEmpty ? "" : cleanCommand)
        \(project.startCommand)
        """

        // 异步执行进程
        Task {
            do {
                onOutputUpdate(project.id, "\n[系统] 正在启动进程组...\n命令: \(project.startCommand)\n\n")
                
                let exitCode = try await ModernProcessExecutor.execute(
                    command: command,
                    in: URL(fileURLWithPath: project.path),
                    onStart: onStart,
                    onOutput: { [weak self] output in
                        let cleanOutput = self?.terminalHandler.stripANSICodes(output) ?? output
                        let keywords = ["error", "warn", "failed", "✓", "✗", "listening", "ready", "started"]
                        let lowercased = cleanOutput.lowercased()
                        let shouldLog = keywords.contains { lowercased.contains($0) }
                        let logMessage = String(cleanOutput.prefix(500))
                        Task { @MainActor [weak self] in
                            if shouldLog {
                                self?.logService.info(logMessage, category: project.name)
                            }
                        }
                        onOutputUpdate(project.id, cleanOutput)
                    }
                )
                
                onOutputUpdate(project.id, "\n\n[系统] 进程已结束 (退出码: \(exitCode.exitCode))\n")
            } catch {
                logService.error("执行异常：\(error.localizedDescription)", category: category)
                onOutputUpdate(project.id, "\n[错误] 进程启动失败: \(error.localizedDescription)\n")
            }
        }

        return .success(())
    }

    /// 停止开发服务器
    func stopDevServer(
        for project: Project,
        category: String,
        cleanCommand: String,
        onOutputUpdate: @escaping @Sendable (UUID, String) -> Void
    ) async -> Result<Void, ProjectServiceError> {
        logService.info("停止开发服务器：\(project.name)", category: category)
        onOutputUpdate(project.id, "\n\n[系统] 正在请求停止进程组...\n")

        let result: Result<Void, ProjectServiceError>
        if let pid = project.runningProcessPID {
            result = await processService.stopProcess(pid: pid)
        } else {
            result = await processService.killProcessByPath(project.path)
        }

        if case .success = result {
            logService.success("成功停止开发服务器：\(project.name)", category: category)
            scheduleCleanup(for: project, category: category, cleanCommand: cleanCommand, onOutputUpdate: onOutputUpdate)
        }

        return result
    }

    private func scheduleCleanup(
        for project: Project,
        category: String,
        cleanCommand: String,
        onOutputUpdate: @escaping @Sendable (UUID, String) -> Void
    ) {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = gitService.cleanCache(at: project.path, command: cleanCommand)
            onOutputUpdate(project.id, "[系统] 缓存清理完成\n")
        }
    }
}
