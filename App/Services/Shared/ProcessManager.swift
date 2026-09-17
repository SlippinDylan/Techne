//
//  ProcessManager.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

enum ProjectStartupCompletion: Sendable, Equatable {
    case exited(exitCode: Int32)
    case executionFailed(description: String)
}

/// 进程管理器
/// 统一管理项目进程的启动、停止和监控
@MainActor
class ProcessManager {
    private let processService: ProcessService
    private let logService = LogService.shared
    private let terminalHandler = TerminalOutputHandler()

    init(processService: ProcessService = .shared) {
        self.processService = processService
    }

    // MARK: - Process Control

    /// 启动开发服务器
    func startProject(
        for project: Project,
        category: String,
        plan: ProjectStartupPlan,
        onStart: @escaping @Sendable (Int32) -> Void,
        onEvent: @escaping @Sendable (ProjectStartupEvent) -> Void,
        onCompletion: @escaping @Sendable (ProjectStartupCompletion) -> Void,
        onOutputUpdate: @escaping @Sendable (UUID, String) -> Void
    ) -> Result<Void, ProjectServiceError> {
        logService.info("准备启动开发服务器：\(project.name)", category: category)
        let terminalHandler = terminalHandler
        let startupOutputInterpreter = StartupOutputInterpreter()
        let startupStateTracker = StartupStateTracker()

        // 异步执行进程
        Task {
            do {
                for message in plan.messages {
                    logService.info(message, category: project.name)
                    onOutputUpdate(project.id, "\(message)\n")
                }

                let startMessage = "\(ProjectStartupCoordinator.startPhaseMessagePrefix)\(project.startCommand)"
                onOutputUpdate(project.id, "\n[系统] 正在启动进程组...\n命令: \(project.startCommand)\n\n")
                
                let result = try await ModernProcessExecutor.execute(
                    command: plan.shellScript,
                    in: URL(fileURLWithPath: project.path),
                    onStart: { pid in
                        onStart(pid)
                        if startupStateTracker.registerProcessStart(pid: pid) {
                            onEvent(.startCommandStarted(pid: pid))
                        }
                    },
                    onOutput: { output in
                        let cleanOutput = terminalHandler.stripANSICodes(output)
                        let interpreted = startupOutputInterpreter.consume(cleanOutput)
                        let events = Self.normalizedStartupEvents(
                            from: interpreted.events,
                            visibleOutput: interpreted.visibleOutput
                        )

                        events.forEach { event in
                            onEvent(event)
                            if case .phaseStarted(.start) = event,
                               let pid = startupStateTracker.registerStartPhaseReached() {
                                onEvent(.startCommandStarted(pid: pid))
                            }
                        }
                        Self.forwardVisibleStartupOutput(
                            interpreted.visibleOutput,
                            startMessage: startMessage,
                            projectName: project.name,
                            onOutputUpdate: {
                                onOutputUpdate(project.id, $0)
                            }
                        )
                    }
                )

                let finalInterpreted = startupOutputInterpreter.consume(
                    terminalHandler.stripANSICodes(result.finalOutput)
                )
                let finalEvents = Self.normalizedStartupEvents(
                    from: finalInterpreted.events,
                    visibleOutput: finalInterpreted.visibleOutput
                )
                finalEvents.forEach { event in
                    onEvent(event)
                    if case .phaseStarted(.start) = event,
                       let pid = startupStateTracker.registerStartPhaseReached() {
                        onEvent(.startCommandStarted(pid: pid))
                    }
                }
                Self.forwardVisibleStartupOutput(
                    finalInterpreted.visibleOutput,
                    startMessage: startMessage,
                    projectName: project.name,
                    onOutputUpdate: {
                        onOutputUpdate(project.id, $0)
                    }
                )

                let pendingInterpreted = startupOutputInterpreter.flush()
                let pendingEvents = Self.normalizedStartupEvents(
                    from: pendingInterpreted.events,
                    visibleOutput: pendingInterpreted.visibleOutput
                )
                pendingEvents.forEach { event in
                    onEvent(event)
                    if case .phaseStarted(.start) = event,
                       let pid = startupStateTracker.registerStartPhaseReached() {
                        onEvent(.startCommandStarted(pid: pid))
                    }
                }
                Self.forwardVisibleStartupOutput(
                    pendingInterpreted.visibleOutput,
                    startMessage: startMessage,
                    projectName: project.name,
                    onOutputUpdate: {
                        onOutputUpdate(project.id, $0)
                    }
                )
                
                onOutputUpdate(project.id, "\n\n[系统] 进程已结束 (退出码: \(result.exitCode))\n")
                onCompletion(.exited(exitCode: result.exitCode))
            } catch {
                logService.error("执行异常：\(error.localizedDescription)", category: category)
                onOutputUpdate(project.id, "\n[错误] 进程启动失败: \(error.localizedDescription)\n")
                onCompletion(.executionFailed(description: error.localizedDescription))
            }
        }

        return .success(())
    }

    private nonisolated static func forwardVisibleStartupOutput(
        _ output: String,
        startMessage: String,
        projectName: String,
        onOutputUpdate: (String) -> Void
    ) {
        guard !output.isEmpty else { return }

        let keywords = ["error", "warn", "failed", "✓", "✗", "listening", "ready", "started"]
        let lowercased = output.lowercased()
        let shouldLog = keywords.contains { lowercased.contains($0) } || output.contains(startMessage)
        let logMessage = String(output.prefix(500))

        if shouldLog {
            Self.logVisibleStartupOutput(logMessage, category: projectName)
        }

        onOutputUpdate(output)
    }

    private nonisolated static func logVisibleStartupOutput(_ message: String, category: String) {
        Task { @MainActor in
            LogService.shared.info(message, category: category)
        }
    }

    private nonisolated static func normalizedStartupEvents(
        from events: [ProjectStartupEvent],
        visibleOutput: String
    ) -> [ProjectStartupEvent] {
        guard events.contains(.phaseStarted(.start)) == false,
              ProjectStartupCoordinator.containsStartPhaseMessage(visibleOutput) else {
            return events
        }

        return events + [.phaseStarted(.start)]
    }

    /// 停止开发服务器
    func stopDevServer(
        for project: Project,
        category: String,
        onOutputUpdate: @escaping @Sendable (UUID, String) -> Void
    ) async -> Result<Void, ProjectServiceError> {
        logService.info("停止开发服务器：\(project.name)", category: category)
        onOutputUpdate(project.id, "\n\n[系统] 正在请求停止进程组...\n")

        let result = await processService.stopProjectProcesses(
            at: project.path,
            preferredPID: project.runningProcessPID
        )

        if case .success = result {
            logService.success("成功停止开发服务器：\(project.name)", category: category)
        }

        return result
    }
}

private final class StartupOutputInterpreter: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var pendingControlLineBuffer = ""

    nonisolated func consume(_ output: String) -> (events: [ProjectStartupEvent], visibleOutput: String) {
        guard !output.isEmpty else {
            return ([], "")
        }

        lock.lock()
        defer { lock.unlock() }

        pendingControlLineBuffer += output

        var events: [ProjectStartupEvent] = []
        var visibleOutput = ""
        let lines = pendingControlLineBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        let hasTrailingNewline = pendingControlLineBuffer.hasSuffix("\n")
        let completeLineCount = hasTrailingNewline ? lines.count : max(lines.count - 1, 0)

        for index in 0..<completeLineCount {
            let line = String(lines[index])
            if let event = ProjectStartupCoordinator.event(forControlLine: line) {
                events.append(event)
            } else {
                visibleOutput += line
                visibleOutput += "\n"
            }
        }

        pendingControlLineBuffer = hasTrailingNewline ? "" : String(lines.last ?? "")
        return (events, visibleOutput)
    }

    nonisolated func flush() -> (events: [ProjectStartupEvent], visibleOutput: String) {
        lock.lock()
        defer {
            pendingControlLineBuffer = ""
            lock.unlock()
        }

        guard !pendingControlLineBuffer.isEmpty else {
            return ([], "")
        }

        if let event = ProjectStartupCoordinator.event(forControlLine: pendingControlLineBuffer) {
            return ([event], "")
        }

        return ([], pendingControlLineBuffer)
    }
}

private final class StartupStateTracker: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var shellPID: Int32?
    nonisolated(unsafe) private var startPhaseReached = false
    nonisolated(unsafe) private var emittedStartCommandStarted = false

    nonisolated
    func registerProcessStart(pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        shellPID = pid
        guard startPhaseReached, emittedStartCommandStarted == false else { return false }
        emittedStartCommandStarted = true
        return true
    }

    nonisolated
    func registerStartPhaseReached() -> Int32? {
        lock.lock()
        defer { lock.unlock() }

        startPhaseReached = true
        guard emittedStartCommandStarted == false, let shellPID else { return nil }
        emittedStartCommandStarted = true
        return shellPID
    }
}
