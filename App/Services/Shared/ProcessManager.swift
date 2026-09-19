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
    private struct ManagedExecution {
        let runID: UUID
        let task: Task<Void, Never>
    }

    private let processService: ProcessService
    private let logService = LogService.shared
    private let terminalHandler = TerminalOutputHandler()
    private var managedExecutions: [UUID: ManagedExecution] = [:]

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
        guard managedExecutions[project.id] == nil else {
            return .failure(.processStartFailed(AppLocalized("error.process.managed_process_already_running")))
        }

        logService.info(AppLocalizedFormat("log.process.preparing_start", project.name), category: category)
        let logService = logService
        let terminalHandler = terminalHandler
        let startupOutputInterpreter = StartupOutputInterpreter()
        let startupStateTracker = StartupStateTracker()
        let runID = UUID()

        let task = Task { [weak self] in
            do {
                for message in plan.messages {
                    logService.info(message, category: project.name)
                    onOutputUpdate(project.id, "\(message)\n")
                }

                let startMessage = ProjectStartupCoordinator.startPhaseMessage(command: project.startCommand)
                onOutputUpdate(
                    project.id,
                    AppLocalizedFormat("terminal.process.starting_group", project.startCommand)
                )
                
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
                
                onOutputUpdate(project.id, AppLocalizedFormat("terminal.process.exited", result.exitCode))
                onCompletion(.exited(exitCode: result.exitCode))
            } catch {
                logService.error(AppLocalizedFormat("log.process.execution_failed", error.localizedDescription), category: category)
                onOutputUpdate(project.id, AppLocalizedFormat("terminal.process.start_failed", error.localizedDescription))
                onCompletion(.executionFailed(description: error.localizedDescription))
            }
            self?.finishManagedExecution(projectID: project.id, runID: runID)
        }
        managedExecutions[project.id] = ManagedExecution(runID: runID, task: task)

        return .success(())
    }

    private func finishManagedExecution(projectID: UUID, runID: UUID) {
        guard managedExecutions[projectID]?.runID == runID else { return }
        managedExecutions[projectID] = nil
    }

    func cancelManagedExecution(for projectID: UUID) {
        managedExecutions[projectID]?.task.cancel()
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
        logService.info(AppLocalizedFormat("log.process.stopping", project.name), category: category)
        onOutputUpdate(project.id, AppLocalized("terminal.process.requesting_stop"))

        let result: Result<Void, ProjectServiceError>
        if let managedExecution = managedExecutions[project.id] {
            managedExecution.task.cancel()
            await managedExecution.task.value
            finishManagedExecution(projectID: project.id, runID: managedExecution.runID)
            result = .success(())
        } else {
            result = await processService.stopProjectProcesses(
                at: project.path,
                preferredPID: project.runningProcessPID
            )
        }

        if case .success = result {
            logService.success(AppLocalizedFormat("log.process.stopped", project.name), category: category)
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
