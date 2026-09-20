//
//  ProcessService.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

enum ProjectProcessStopOutcome: Equatable, Sendable {
    case notFound
    case stopped
}

/// 进程管理服务
/// 提供统一的进程启动、停止、监控接口
final class ProcessService: Sendable {
    struct Runtime: Sendable {
        let processSnapshots: @Sendable () async -> [ProjectProcessSnapshot]
        let processSnapshotForPID: @Sendable (Int32) async -> ProjectProcessSnapshot?
        let processIDsInGroup: @Sendable (Int32) async -> [Int32]
        let processGroupID: @Sendable (Int32) -> Int32
        let sendSignalToProcessGroup: @Sendable (Int32, Int32) -> Void
        let sendSignalToProcess: @Sendable (Int32, Int32) -> Void
        let isProcessRunning: @Sendable (Int32) async -> Bool
        let sleep: @Sendable (UInt64) async -> Void
    }

    nonisolated static let shared = ProcessService()

    private let runtime: Runtime

    nonisolated init(runtime: Runtime = .live) {
        self.runtime = runtime
    }

    // MARK: - Public Methods

    nonisolated func processSnapshots() async -> [ProjectProcessSnapshot] {
        await runtime.processSnapshots()
    }

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
            return await stopProcessGroup(
                processGroupID: pgid,
                verificationPIDs: await verificationPIDsForProcessGroup(processGroupID: pgid, fallbackPID: pid),
                fallbackPIDs: [pid]
            )
        }

        return await stopSingleProcess(pid: pid)
    }

    func stopProjectProcesses(for project: Project) async -> Result<Void, ProjectServiceError> {
        let result = await stopAllProjectProcessesIfPresent(for: project)
        switch result {
        case .success(.stopped):
            return .success(())
        case .success(.notFound):
            return .failure(.processStopFailed(AppLocalized("error.process.no_matching_project_process")))
        case .failure(let error):
            return .failure(error)
        }
    }

    func stopAllProjectProcessesIfPresent(
        for project: Project,
        using snapshots: [ProjectProcessSnapshot]? = nil
    ) async -> Result<ProjectProcessStopOutcome, ProjectServiceError> {
        let processSnapshots = if let snapshots {
            snapshots
        } else {
            await runtime.processSnapshots()
        }
        guard let runtimeMatch = ProjectRuntimeProcessMatcher.matches(
            for: project,
            in: processSnapshots
        ) else {
            return .success(.notFound)
        }

        var failureMessages: [String] = []

        for processGroupID in runtimeMatch.processGroupIDs {
            let verificationPIDs = processSnapshots
                .filter { $0.processGroupID == processGroupID }
                .map(\.pid)
            let fallbackPIDs = processSnapshots
                .filter {
                    $0.processGroupID == processGroupID &&
                        ProjectProcessScope.contains(process: $0, projectRootPath: project.path)
                }
                .map(\.pid)
            let result = await stopProcessGroup(
                processGroupID: processGroupID,
                verificationPIDs: verificationPIDs,
                fallbackPIDs: fallbackPIDs
            )
            if case .failure(let error) = result {
                failureMessages.append(AppLocalizedFormat("error.process.group_failure", processGroupID, error.localizedDescription))
            }
        }

        guard failureMessages.isEmpty else {
            return .failure(.processStopFailed(failureMessages.joined(separator: "; ")))
        }

        return .success(.stopped)
    }

    private func stopProcessGroup(
        processGroupID: Int32,
        verificationPIDs: [Int32],
        fallbackPIDs: [Int32]
    ) async -> Result<Void, ProjectServiceError> {
        if processGroupID == getpgrp() {
            for pid in fallbackPIDs {
                let result = await stopSingleProcess(pid: pid)
                if case .failure = result {
                    return result
                }
            }
            return .success(())
        }

        runtime.sendSignalToProcessGroup(processGroupID, SIGINT)
        if await waitUntilProcessesStop(verificationPIDs, attempts: 6) {
            return .success(())
        }

        runtime.sendSignalToProcessGroup(processGroupID, SIGTERM)
        if await waitUntilProcessesStop(verificationPIDs, attempts: 4) {
            return .success(())
        }

        runtime.sendSignalToProcessGroup(processGroupID, SIGKILL)
        if await waitUntilProcessesStop(verificationPIDs, attempts: 2) == false {
            return .failure(.processStopFailed(AppLocalizedFormat("error.process.group_force_stop_failed", processGroupID)))
        }

        return .success(())
    }

    private func stopSingleProcess(pid: Int32) async -> Result<Void, ProjectServiceError> {
        runtime.sendSignalToProcess(pid, SIGINT)
        if await waitUntilProcessesStop([pid], attempts: 6) {
            return .success(())
        }

        runtime.sendSignalToProcess(pid, SIGTERM)
        if await waitUntilProcessesStop([pid], attempts: 4) {
            return .success(())
        }

        runtime.sendSignalToProcess(pid, SIGKILL)
        if await waitUntilProcessesStop([pid], attempts: 2) == false {
            return .failure(.processStopFailed(AppLocalizedFormat("error.process.stop_failed", pid)))
        }

        return .success(())
    }

    private func verificationPIDsForProcessGroup(
        processGroupID: Int32,
        fallbackPID: Int32
    ) async -> [Int32] {
        let processIDs = await runtime.processIDsInGroup(processGroupID)
        return processIDs.isEmpty ? [fallbackPID] : processIDs
    }

    private func anyProcessRunning(in processIDs: [Int32]) async -> Bool {
        for pid in processIDs {
            if await runtime.isProcessRunning(pid) {
                return true
            }
        }

        return false
    }

    private func waitUntilProcessesStop(_ processIDs: [Int32], attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if await anyProcessRunning(in: processIDs) == false {
                return true
            }
            await runtime.sleep(50_000_000)
        }

        return await anyProcessRunning(in: processIDs) == false
    }

    nonisolated private static func loadProjectProcessSnapshots() async -> [ProjectProcessSnapshot] {
        let currentWorkingDirectories = await loadCurrentWorkingDirectories()
        let task = SystemProcessInspector.makeProcessListTask()

        do {
            let result = try await ProcessUtils.runAndCapture(task)
            guard result.terminationStatus == 0 else { return [] }
            guard let decodedOutput = String(data: result.standardOutput, encoding: .utf8) else {
                return []
            }

            return SystemProcessInspector.parseProcessSnapshots(
                from: decodedOutput,
                currentWorkingDirectories: currentWorkingDirectories
            )
        } catch {
            return []
        }
    }

    nonisolated private static func loadProjectProcessSnapshot(pid: Int32) async -> ProjectProcessSnapshot? {
        async let commandLine = loadCommandLine(for: pid)
        async let currentWorkingDirectory = loadCurrentWorkingDirectory(for: pid)

        let processGroupID = getpgid(pid)
        let resolvedCommandLine = await commandLine
        let resolvedWorkingDirectory = await currentWorkingDirectory

        guard processGroupID > 0 || resolvedCommandLine?.isEmpty == false || resolvedWorkingDirectory != nil else {
            return nil
        }

        return ProjectProcessSnapshot(
            pid: pid,
            processGroupID: processGroupID,
            commandLine: resolvedCommandLine ?? "",
            currentWorkingDirectory: resolvedWorkingDirectory
        )
    }

    nonisolated private static func loadCurrentWorkingDirectories() async -> [Int32: String] {
        guard let task = SystemProcessInspector.makeCurrentWorkingDirectoryTask() else {
            return [:]
        }

        do {
            let result = try await ProcessUtils.runAndCapture(task)
            guard result.terminationStatus == 0 else { return [:] }
            guard let decodedOutput = String(data: result.standardOutput, encoding: .utf8) else {
                return [:]
            }

            return SystemProcessInspector.parseCurrentWorkingDirectories(from: decodedOutput)
        } catch {
            return [:]
        }
    }

    nonisolated private static func loadCurrentWorkingDirectory(for pid: Int32) async -> String? {
        guard let task = SystemProcessInspector.makeCurrentWorkingDirectoryTask(pid: pid) else {
            return nil
        }

        do {
            let result = try await ProcessUtils.runAndCapture(task)
            guard result.terminationStatus == 0,
                  let decodedOutput = String(data: result.standardOutput, encoding: .utf8) else {
                return nil
            }

            return SystemProcessInspector.parseCurrentWorkingDirectories(from: decodedOutput)[pid]
        } catch {
            return nil
        }
    }

    nonisolated private static func loadCommandLine(for pid: Int32) async -> String? {
        let task = SystemProcessInspector.makeCommandLineTask(pid: pid)

        do {
            let result = try await ProcessUtils.runAndCapture(task)
            guard result.terminationStatus == 0,
                  let decodedOutput = String(data: result.standardOutput, encoding: .utf8) else {
                return nil
            }

            let commandLine = decodedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return commandLine.isEmpty ? nil : commandLine
        } catch {
            return nil
        }
    }

    nonisolated private static func loadProcessIDs(inProcessGroup processGroupID: Int32) async -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-g", String(processGroupID)]

        do {
            let result = try await ProcessUtils.runAndCapture(task)
            guard result.terminationStatus == 0,
                  let output = String(data: result.standardOutput, encoding: .utf8) else {
                return []
            }

            return output
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        } catch {
            return []
        }
    }

    nonisolated private static func isProcessRunning(pid: Int32) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid)]

        do {
            let result = try await ProcessUtils.runAndCapture(task)
            return result.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension ProcessService.Runtime {
    nonisolated static let live = ProcessService.Runtime(
        processSnapshots: {
            await ProcessService.loadProjectProcessSnapshots()
        },
        processSnapshotForPID: { pid in
            await ProcessService.loadProjectProcessSnapshot(pid: pid)
        },
        processIDsInGroup: { processGroupID in
            await ProcessService.loadProcessIDs(inProcessGroup: processGroupID)
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
            await ProcessService.isProcessRunning(pid: pid)
        },
        sleep: { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    )
}
