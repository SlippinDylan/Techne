import Darwin
import Foundation

struct ManagedBrowserInstanceService: Sendable {
    enum SignalResult: Sendable {
        case delivered
        case notRunning
        case failed
    }

    struct TerminationResult: Equatable, Sendable {
        let matchedInstanceNames: [String]
        let terminatedPIDs: [Int32]
        let failedPIDs: [Int32]

        var matchedCount: Int { matchedInstanceNames.count }
    }

    private let instanceStore: BrowserInstanceStore
    private let sendSignal: @Sendable (Int32, Int32) -> SignalResult
    private let isProcessRunning: @Sendable (Int32) -> Bool
    private let sleep: @Sendable (Duration) async -> Void

    nonisolated init(
        instanceStore: BrowserInstanceStore = BrowserInstanceStore(),
        sendSignal: @escaping @Sendable (Int32, Int32) -> SignalResult = Self.defaultSendSignal(pid:signal:),
        isProcessRunning: @escaping @Sendable (Int32) -> Bool = Self.defaultIsProcessRunning(pid:),
        sleep: @escaping @Sendable (Duration) async -> Void = Self.defaultSleep(duration:)
    ) {
        self.instanceStore = instanceStore
        self.sendSignal = sendSignal
        self.isProcessRunning = isProcessRunning
        self.sleep = sleep
    }

    nonisolated func terminateManagedInstances(forProjectPath projectPath: String) async throws -> TerminationResult {
        guard let normalizedProjectPath = Self.normalizeProjectPath(projectPath) else {
            return TerminationResult(matchedInstanceNames: [], terminatedPIDs: [], failedPIDs: [])
        }

        let trackedInstances = try instanceStore.loadTrackedInstances()
        let matchingInstances = trackedInstances.filter { record in
            record.launchTarget?.projectPath == normalizedProjectPath
        }

        var terminatedPIDs: [Int32] = []
        var failedPIDs: [Int32] = []

        for record in matchingInstances {
            let didTerminate = await terminateProcess(pid: record.pid)
            if didTerminate {
                try? instanceStore.removeTrackedInstance(
                    named: record.instanceName,
                    profileDirectoryPath: record.profileDirectoryPath
                )
                terminatedPIDs.append(record.pid)
            } else {
                failedPIDs.append(record.pid)
            }
        }

        return TerminationResult(
            matchedInstanceNames: matchingInstances.map(\.instanceName),
            terminatedPIDs: terminatedPIDs,
            failedPIDs: failedPIDs
        )
    }

    private nonisolated func terminateProcess(pid: Int32) async -> Bool {
        guard isProcessRunning(pid) else {
            return true
        }

        switch sendSignal(pid, SIGTERM) {
        case .failed:
            return false
        case .notRunning:
            return true
        case .delivered:
            break
        }

        if await waitUntilProcessStops(pid: pid) {
            return true
        }

        switch sendSignal(pid, SIGKILL) {
        case .failed:
            return false
        case .notRunning:
            return true
        case .delivered:
            return await waitUntilProcessStops(pid: pid)
        }
    }

    private nonisolated func waitUntilProcessStops(pid: Int32) async -> Bool {
        for _ in 0..<6 {
            await sleep(.milliseconds(200))
            if isProcessRunning(pid) == false {
                return true
            }
        }

        return isProcessRunning(pid) == false
    }

    private nonisolated static func normalizeProjectPath(_ path: String?) -> String? {
        guard let path else { return nil }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return nil }

        return URL(fileURLWithPath: trimmedPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private nonisolated static func defaultSendSignal(pid: Int32, signal: Int32) -> SignalResult {
        if kill(pid, signal) == 0 {
            return .delivered
        }

        return errno == ESRCH ? .notRunning : .failed
    }

    private nonisolated static func defaultIsProcessRunning(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private nonisolated static func defaultSleep(duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
