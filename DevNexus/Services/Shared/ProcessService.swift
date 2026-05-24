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
    struct Runtime: Sendable {
        let processSnapshots: @Sendable () async -> [ProjectProcessSnapshot]
        let processGroupID: @Sendable (Int32) -> Int32
        let sendSignalToProcessGroup: @Sendable (Int32, Int32) -> Void
        let sendSignalToProcess: @Sendable (Int32, Int32) -> Void
        let isProcessRunning: @Sendable (Int32) -> Bool
        let sleep: @Sendable (UInt64) async -> Void
    }

    nonisolated static let shared = ProcessService()

    private let runtime: Runtime

    nonisolated init(runtime: Runtime = .live) {
        self.runtime = runtime
    }

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
        guard let parsedPID = Int32(pid) else { return false }
        let task = SystemProcessInspector.makeCommandLineTask(pid: parsedPID)

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
        let pgid = runtime.processGroupID(pid)
        if pgid > 0 {
            return await stopProcessGroup(processGroupID: pgid, verificationPIDs: [pid])
        }

        return await stopSingleProcess(pid: pid)
    }

    /// 使用项目根目录停止进程
    func stopProjectProcesses(at projectRootPath: String) async -> Result<Void, ProjectServiceError> {
        let processSnapshots = await runtime.processSnapshots()
        let plan = ProjectRootProcessMatcher.stopPlan(
            forProjectRootPath: projectRootPath,
            processes: processSnapshots
        )

        guard plan.isEmpty == false else {
            return .failure(.processStopFailed("未找到匹配项目路径的运行进程"))
        }

        var failureMessages: [String] = []

        for processGroupID in plan.processGroupIDs {
            let verificationPIDs = processSnapshots
                .filter { $0.processGroupID == processGroupID }
                .map(\.pid)
            let result = await stopProcessGroup(
                processGroupID: processGroupID,
                verificationPIDs: verificationPIDs
            )
            if case .failure(let error) = result {
                failureMessages.append("进程组 \(processGroupID): \(error.localizedDescription)")
            }
        }

        for pid in plan.fallbackProcessIDs {
            let result = await stopSingleProcess(pid: pid)
            if case .failure(let error) = result {
                failureMessages.append("进程 \(pid): \(error.localizedDescription)")
            }
        }

        guard failureMessages.isEmpty else {
            return .failure(.processStopFailed(failureMessages.joined(separator: "; ")))
        }

        return .success(())
    }

    /// 使用路径停止进程 (兼容旧调用，内部改为项目根目录范围)
    func killProcessByPath(_ path: String) async -> Result<Void, ProjectServiceError> {
        await stopProjectProcesses(at: path)
    }

    nonisolated private func isProcessStillRunning(pid: String) -> Bool {
        guard let parsedPID = Int32(pid) else { return false }
        return runtime.isProcessRunning(parsedPID)
    }

    private func stopProcessGroup(
        processGroupID: Int32,
        verificationPIDs: [Int32]
    ) async -> Result<Void, ProjectServiceError> {
        runtime.sendSignalToProcessGroup(processGroupID, SIGTERM)
        await runtime.sleep(500_000_000)

        if verificationPIDs.contains(where: runtime.isProcessRunning) {
            runtime.sendSignalToProcessGroup(processGroupID, SIGKILL)
            await runtime.sleep(200_000_000)
        }

        if verificationPIDs.contains(where: runtime.isProcessRunning) {
            return .failure(.processStopFailed("进程组 (\(processGroupID)) 强制停止无效，可能存在权限限制"))
        }

        return .success(())
    }

    private func stopSingleProcess(pid: Int32) async -> Result<Void, ProjectServiceError> {
        runtime.sendSignalToProcess(pid, SIGTERM)
        await runtime.sleep(500_000_000)

        if runtime.isProcessRunning(pid) {
            runtime.sendSignalToProcess(pid, SIGKILL)
            await runtime.sleep(200_000_000)
        }

        if runtime.isProcessRunning(pid) {
            return .failure(.processStopFailed("进程 \(pid) 停止失败"))
        }

        return .success(())
    }

    nonisolated private static func loadProjectProcessSnapshots() async -> [ProjectProcessSnapshot] {
        let currentWorkingDirectories = loadCurrentWorkingDirectories()
        let task = SystemProcessInspector.makeProcessListTask()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ProcessService")
            guard terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return SystemProcessInspector.parseProcessSnapshots(
                from: output,
                currentWorkingDirectories: currentWorkingDirectories
            )
        } catch {
            return []
        }
    }

    nonisolated private static func loadCurrentWorkingDirectories() -> [Int32: String] {
        guard let task = SystemProcessInspector.makeCurrentWorkingDirectoryTask() else {
            return [:]
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ProcessService")
            guard terminationStatus == 0 else { return [:] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return [:]
            }

            return SystemProcessInspector.parseCurrentWorkingDirectories(from: output)
        } catch {
            return [:]
        }
    }
}

extension ProcessService.Runtime {
    nonisolated static let live = ProcessService.Runtime(
        processSnapshots: {
            await ProcessService.loadProjectProcessSnapshots()
        },
        processGroupID: { pid in
            getpgid(pid)
        },
        sendSignalToProcessGroup: { processGroupID, signal in
            kill(-processGroupID, signal)
        },
        sendSignalToProcess: { pid, signal in
            kill(pid, signal)
        },
        isProcessRunning: { pid in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-p", String(pid)]
            task.standardOutput = Pipe()
            task.standardError = Pipe()

            do {
                let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ProcessService")
                return terminationStatus == 0
            } catch {
                return false
            }
        },
        sleep: { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    )
}
