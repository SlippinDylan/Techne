import Darwin
import Foundation
import Testing
@testable import Techne

struct ManagedBrowserInstanceServiceTests {
    @Test
    func terminateManagedInstancesRemovesOnlyMatchedProjectRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = BrowserInstanceStore(rootDirectoryURL: root)
        let targetRecord = try makeRecord(
            store: store,
            instanceName: "matched-browser",
            projectPath: "/Users/test/workspace/app-a",
            port: 5173
        )
        let otherProjectRecord = try makeRecord(
            store: store,
            instanceName: "other-browser",
            projectPath: "/Users/test/workspace/app-b",
            port: 5174
        )
        let noProjectRecord = try makeRecord(
            store: store,
            instanceName: "port-only-browser",
            projectPath: nil,
            port: 5173
        )

        let recorder = SignalRecorder(runningPIDs: [targetRecord.pid, otherProjectRecord.pid, noProjectRecord.pid])
        let service = ManagedBrowserInstanceService(
            instanceStore: store,
            sendSignal: recorder.send(pid:signal:),
            isProcessRunning: recorder.isRunning(pid:),
            sleep: { _ in }
        )

        let result = try await service.terminateManagedInstances(forProjectPath: "/Users/test/workspace/app-a")

        #expect(result.matchedInstanceNames == ["matched-browser"])
        #expect(result.terminatedPIDs == [targetRecord.pid])
        #expect(result.failedPIDs.isEmpty)
        #expect(recorder.signals == [SignalEvent(pid: targetRecord.pid, signal: SIGTERM)])

        let remainingNames = try store.loadTrackedInstances().map(\.instanceName).sorted()
        #expect(remainingNames == ["other-browser", "port-only-browser"])
    }

    @Test
    func terminateManagedInstancesMatchesTrackedRecordsAcrossSymlinkedPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let realProjectURL = root.appendingPathComponent("real-project", isDirectory: true)
        let symlinkProjectURL = root.appendingPathComponent("project-link", isDirectory: false)
        try FileManager.default.createDirectory(at: realProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkProjectURL, withDestinationURL: realProjectURL)

        let store = BrowserInstanceStore(rootDirectoryURL: root.appendingPathComponent("store", isDirectory: true))
        let record = try makeRecord(
            store: store,
            instanceName: "symlinked-browser",
            projectPath: realProjectURL.path,
            port: 3000
        )

        let recorder = SignalRecorder(runningPIDs: [record.pid])
        let service = ManagedBrowserInstanceService(
            instanceStore: store,
            sendSignal: recorder.send(pid:signal:),
            isProcessRunning: recorder.isRunning(pid:),
            sleep: { _ in }
        )

        let result = try await service.terminateManagedInstances(forProjectPath: symlinkProjectURL.path)

        #expect(result.terminatedPIDs == [record.pid])
        #expect(recorder.signals == [SignalEvent(pid: record.pid, signal: SIGTERM)])
        #expect(try store.loadTrackedInstances().isEmpty)
    }

    @Test
    func terminateManagedInstancesKeepsTrackedRecordWhenTerminationFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = BrowserInstanceStore(rootDirectoryURL: root)
        let record = try makeRecord(
            store: store,
            instanceName: "failing-browser",
            projectPath: "/Users/test/workspace/app-a",
            port: 8080
        )

        let service = ManagedBrowserInstanceService(
            instanceStore: store,
            sendSignal: { _, _ in .failed },
            isProcessRunning: { _ in true },
            sleep: { _ in }
        )

        let result = try await service.terminateManagedInstances(forProjectPath: "/Users/test/workspace/app-a")

        #expect(result.matchedInstanceNames == ["failing-browser"])
        #expect(result.terminatedPIDs.isEmpty)
        #expect(result.failedPIDs == [record.pid])
        #expect(try store.loadTrackedInstances().map(\.instanceName) == ["failing-browser"])
    }

    private func makeRecord(
        store: BrowserInstanceStore,
        instanceName: String,
        projectPath: String?,
        port: Int
    ) throws -> BrowserInstanceRecord {
        let profileDirectory = store.profilesDirectoryURL.appendingPathComponent(instanceName, isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let record = BrowserInstanceRecord(
            instanceName: instanceName,
            pid: getpid(),
            browserName: "Google Chrome",
            browserBundleID: BrowserType.chrome.bundleId,
            browserAppPath: "/Applications/Google Chrome.app",
            launchedURL: "http://localhost:\(port)",
            debugPort: 9222 + port,
            profileDirectoryPath: profileDirectory.path,
            startedAt: Date(timeIntervalSince1970: 1_716_100_000 + TimeInterval(port)),
            launchTarget: BrowserLaunchTarget(
                launchSource: "project-card",
                serverPort: port,
                projectPath: projectPath
            )
        )

        try store.save(record)
        return record
    }
}

private final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var runningPIDs: Set<Int32>
    nonisolated(unsafe) private(set) var signals: [SignalEvent] = []

    init(runningPIDs: Set<Int32>) {
        self.runningPIDs = runningPIDs
    }

    nonisolated
    func send(pid: Int32, signal: Int32) -> ManagedBrowserInstanceService.SignalResult {
        lock.lock()
        defer { lock.unlock() }

        guard runningPIDs.contains(pid) else {
            return .notRunning
        }

        signals.append(SignalEvent(pid: pid, signal: signal))

        if signal == SIGTERM || signal == SIGKILL {
            runningPIDs.remove(pid)
            return .delivered
        }

        return .failed
    }

    nonisolated
    func isRunning(pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningPIDs.contains(pid)
    }
}

private struct SignalEvent: Equatable {
    let pid: Int32
    let signal: Int32
}
