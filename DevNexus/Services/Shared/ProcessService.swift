//
//  ProcessService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 进程管理服务
/// 提供统一的进程启动、停止、监控接口
final class ProcessService: Sendable {
    nonisolated static let shared = ProcessService()

    nonisolated private init() {}

    // MARK: - Public Methods

    /// 检查进程是否在运行 (增强版：路径 + 关键词双重过滤)
    nonisolated func isProcessRunning(at path: String, keywords: [String]) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        // -f 搜索完整命令行，确保路径匹配
        task.arguments = ["-f", path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            
            let status = await withCheckedContinuation { continuation in
                task.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            }

            // pgrep 返回 0 表示找到至少一个匹配路径的进程
            if status == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }

                    for pid in pids {
                        // 核心加固：必须同时匹配业务关键词 (node/vite/uni) 且排除 App 自身的干扰进程
                        if await checkProcessMatchesKeywords(pid: pid, keywords: keywords) {
                            return true
                        }
                    }
                }
            }
        } catch { }

        return false
    }

    /// 检查进程是否匹配关键词 (异步版本)
    nonisolated private func checkProcessMatchesKeywords(pid: String, keywords: [String]) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // 获取完整命令行内容
        task.arguments = ["-p", pid, "-o", "command="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let status = await withCheckedContinuation { continuation in
                task.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            }

            guard status == 0 else { return false }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let command = String(data: data, encoding: .utf8) {
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

                // 排除列表：防止误杀工具类进程
                let excludePatterns = ["/usr/bin/pkill", "/usr/bin/pgrep", "/bin/kill", "rm -rf", "/bin/ps", "grep", "awk"]
                if excludePatterns.contains(where: { trimmedCommand.contains($0) }) { return false }

                // 逻辑：命令中必须包含指定的开发环境关键词 (如 node, vite, pnpm 等)
                return keywords.contains { trimmedCommand.contains($0) }
            }
        } catch { }
        return false
    }

    /// 停止进程（通过进程组高效停止）
    func stopProcess(pid: Int32) async -> Result<Void, ProjectServiceError> {
        let pgid = getpgid(pid)
        if pgid > 0 {
            // 尝试柔和停止
            kill(-pgid, SIGTERM)
            
            // 异步等待清理
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if isProcessStillRunning(pid: String(pid)) {
                // 如果还活着，强制清理
                kill(-pgid, SIGKILL)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            
            // 物理校验：如果依然存活，报失败
            if isProcessStillRunning(pid: String(pid)) {
                return .failure(.processStopFailed("进程组 (\(pgid)) 强制停止无效，可能存在权限限制"))
            }
            return .success(())
        } else {
            kill(pid, SIGTERM)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if isProcessStillRunning(pid: String(pid)) {
                kill(pid, SIGKILL)
            }
            
            if isProcessStillRunning(pid: String(pid)) {
                return .failure(.processStopFailed("进程 \(pid) 停止失败"))
            }
            return .success(())
        }
    }

    /// 使用路径停止进程 (严格校验版)
    func killProcessByPath(_ path: String) async -> Result<Void, ProjectServiceError> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", path]
        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            let status = await withCheckedContinuation { continuation in
                task.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            }

            if status == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }

                var failureMessage = ""
                for pidString in pids {
                    if let pid = Int32(pidString) {
                        let res = await stopProcess(pid: pid)
                        if case .failure(let error) = res {
                            failureMessage += "\(pid): \(error.localizedDescription); "
                        }
                    }
                }
                
                if !failureMessage.isEmpty {
                    return .failure(.processStopFailed("部分进程停止失败: \(failureMessage)"))
                }
                return .success(())
            }
            return .failure(.processStopFailed("未找到匹配路径的进程"))
        } catch {
            return .failure(.processStopFailed(error.localizedDescription))
        }
    }

    nonisolated private func isProcessStillRunning(pid: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", pid]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ProcessService")
            return terminationStatus == 0
        } catch { return false }
    }
}
