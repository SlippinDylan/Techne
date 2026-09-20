import Foundation
import Testing
@testable import Techne

struct ProcessManagerManagedExecutionTests {
    @Test
    @MainActor
    func stopCancelsManagedExecutionAndScansOnceForResidualProcesses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fallbackRecorder = FallbackLookupRecorder()
        let processService = ProcessService(
            runtime: .init(
                processSnapshots: {
                    fallbackRecorder.recordLookup()
                    return []
                },
                processSnapshotForPID: { _ in
                    fallbackRecorder.recordLookup()
                    return nil
                },
                processIDsInGroup: { _ in [] },
                processGroupID: { _ in -1 },
                sendSignalToProcessGroup: { _, _ in },
                sendSignalToProcess: { _, _ in },
                isProcessRunning: { _ in false },
                sleep: { _ in }
            )
        )
        let manager = ProcessManager(processService: processService)
        let project = Project(
            name: "managed-project",
            path: root.path,
            type: .devServer,
            startCommand: "sleep 30",
            installStrategy: .never
        )
        let plan = ProjectStartupCoordinator.makePlan(for: project, fallbackCleanCommand: "")
        let executionRecorder = ManagedExecutionRecorder()

        let startResult = manager.startProject(
            for: project,
            category: "test",
            plan: plan,
            onStart: executionRecorder.recordStart(pid:),
            onEvent: { _ in },
            onCompletion: executionRecorder.recordCompletion(_:),
            onOutputUpdate: { _, _ in }
        )
        guard case .success = startResult else {
            Issue.record("expected managed execution to start")
            return
        }
        let started = await waitUntil { executionRecorder.startedPID() != nil }
        #expect(started)

        let stopResult = await manager.stopDevServer(
            for: project,
            category: "test",
            onOutputUpdate: { _, _ in }
        )

        guard case .success = stopResult else {
            Issue.record("expected managed execution to stop")
            return
        }
        #expect(fallbackRecorder.lookupCount() == 1)
        #expect(executionRecorder.completionCount() == 1)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}

private final class FallbackLookupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var count = 0

    nonisolated func recordLookup() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    nonisolated func lookupCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class ManagedExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var pid: Int32?
    nonisolated(unsafe) private var completions: [ProjectStartupCompletion] = []

    nonisolated func recordStart(pid: Int32) {
        lock.lock()
        self.pid = pid
        lock.unlock()
    }

    nonisolated func recordCompletion(_ completion: ProjectStartupCompletion) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    nonisolated func startedPID() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }

    nonisolated func completionCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }
}
