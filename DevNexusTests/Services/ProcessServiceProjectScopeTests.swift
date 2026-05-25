import Foundation
import Testing
@testable import DevNexus

struct ProcessServiceProjectScopeTests {
    @Test
    func preferredPIDMatchingManagedProjectStopsWithoutGlobalProcessSnapshotScan() async {
        let recorder = ProcessServiceStopRecorder(
            aliveProcessIDs: [99752, 99767],
            processGroupIDs: [
                99752: 99365,
                99767: 99365
            ],
            currentWorkingDirectories: [
                99752: "/Users/test/Portlens",
                99767: "/Users/test/Portlens/app"
            ]
        )
        let service = ProcessService(
            runtime: .init(
                processSnapshots: {
                    recorder.recordSnapshotScan()
                    return []
                },
                processSnapshotForPID: { pid in
                    ProjectProcessSnapshot(
                        pid: pid,
                        processGroupID: recorder.processGroupID(for: pid),
                        commandLine: "node ./scripts/workspace-next.mjs dev mock",
                        currentWorkingDirectory: recorder.currentWorkingDirectory(for: pid)
                    )
                },
                processIDsInGroup: { _ in [99752, 99767] },
                processGroupID: recorder.processGroupID(for:),
                sendSignalToProcessGroup: recorder.sendGroupSignal(groupID:signal:),
                sendSignalToProcess: recorder.sendProcessSignal(pid:signal:),
                isProcessRunning: { pid in recorder.isRunning(pid: pid) },
                sleep: { _ in }
            )
        )

        let result = await service.stopProjectProcesses(
            at: "/Users/test/Portlens",
            preferredPID: 99752
        )

        guard case .success = result else {
            Issue.record("expected preferred PID stop to succeed")
            return
        }

        #expect(recorder.snapshotScanCount() == 0)
        #expect(recorder.groupSignals() == [ProcessSignalEvent(target: 99365, signal: SIGTERM)])
        #expect(recorder.processSignals().isEmpty)
    }

    @Test
    func preferredPIDPathFailsWhenSiblingInSameProcessGroupSurvivesSignals() async {
        let recorder = ProcessServiceStopRecorder(
            aliveProcessIDs: [99752, 99767],
            processGroupIDs: [
                99752: 99365,
                99767: 99365
            ],
            currentWorkingDirectories: [
                99752: "/Users/test/Portlens",
                99767: "/Users/test/Portlens/app"
            ],
            groupSignalSurvivors: [99767]
        )
        let service = ProcessService(
            runtime: .init(
                processSnapshots: {
                    recorder.recordSnapshotScan()
                    return []
                },
                processSnapshotForPID: { pid in
                    ProjectProcessSnapshot(
                        pid: pid,
                        processGroupID: recorder.processGroupID(for: pid),
                        commandLine: "node ./scripts/workspace-next.mjs dev mock",
                        currentWorkingDirectory: recorder.currentWorkingDirectory(for: pid)
                    )
                },
                processIDsInGroup: { _ in [99752, 99767] },
                processGroupID: recorder.processGroupID(for:),
                sendSignalToProcessGroup: recorder.sendGroupSignal(groupID:signal:),
                sendSignalToProcess: recorder.sendProcessSignal(pid:signal:),
                isProcessRunning: { pid in recorder.isRunning(pid: pid) },
                sleep: { _ in }
            )
        )

        let result = await service.stopProjectProcesses(
            at: "/Users/test/Portlens",
            preferredPID: 99752
        )

        guard case .failure = result else {
            Issue.record("expected stop to fail when a sibling process survives both group signals")
            return
        }

        #expect(recorder.snapshotScanCount() == 0)
        #expect(recorder.groupSignals() == [
            ProcessSignalEvent(target: 99365, signal: SIGTERM),
            ProcessSignalEvent(target: 99365, signal: SIGKILL)
        ])
    }

    @Test
    func descendantWorkingDirectoryMatchesManagedProjectRoot() {
        let process = ProjectProcessSnapshot(
            pid: 99767,
            processGroupID: 99365,
            commandLine: "next-server (v15.5.18)",
            currentWorkingDirectory: "/Users/test/Portlens/app"
        )

        #expect(
            ProjectRootProcessMatcher.matches(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            )
        )
    }

    @Test
    func commandLineContainingProjectRootMatchesWhenWorkingDirectoryIsUnavailable() {
        let process = ProjectProcessSnapshot(
            pid: 99752,
            processGroupID: 99365,
            commandLine: "node /Users/test/Portlens/scripts/workspace-next.mjs dev mock",
            currentWorkingDirectory: nil
        )

        #expect(
            ProjectRootProcessMatcher.matches(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            )
        )
    }

    @Test
    func siblingPathsDoNotMatchManagedProjectRoot() {
        let process = ProjectProcessSnapshot(
            pid: 2201,
            processGroupID: 2201,
            commandLine: "node /Users/test/Portlens-docs/scripts/dev.mjs",
            currentWorkingDirectory: "/Users/test/Portlens-docs/app"
        )

        #expect(
            ProjectRootProcessMatcher.matches(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            ) == false
        )
    }

    @Test
    func stopPlanDeduplicatesMatchedProcessGroupsAndIgnoresUnrelatedStoredPID() {
        let plan = ProjectRootProcessMatcher.stopPlan(
            forProjectRootPath: "/Users/test/Portlens",
            processes: [
                ProjectProcessSnapshot(
                    pid: 111,
                    processGroupID: 111,
                    commandLine: "node /tmp/other-project/dev.mjs",
                    currentWorkingDirectory: "/tmp/other-project"
                ),
                ProjectProcessSnapshot(
                    pid: 99751,
                    processGroupID: 99365,
                    commandLine: "node ./scripts/workspace-next.mjs dev mock",
                    currentWorkingDirectory: "/Users/test/Portlens"
                ),
                ProjectProcessSnapshot(
                    pid: 99752,
                    processGroupID: 99365,
                    commandLine: "node /Users/test/Portlens/app/node_modules/next/dist/bin/next dev",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                ),
                ProjectProcessSnapshot(
                    pid: 99767,
                    processGroupID: 99365,
                    commandLine: "next-server (v15.5.18)",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                )
            ]
        )

        #expect(plan.processGroupIDs == [99365])
        #expect(plan.fallbackProcessIDs.isEmpty)
        #expect(plan.matchedPIDs == [99751, 99752, 99767])
    }

    @Test
    func stopPlanDoesNotFallbackToStoredPIDWhenNoProjectScopedProcessMatches() {
        let plan = ProjectRootProcessMatcher.stopPlan(
            forProjectRootPath: "/Users/test/Portlens",
            processes: [
                ProjectProcessSnapshot(
                    pid: 111,
                    processGroupID: 111,
                    commandLine: "node /tmp/other-project/dev.mjs",
                    currentWorkingDirectory: "/tmp/other-project"
                )
            ]
        )

        #expect(plan.processGroupIDs.isEmpty)
        #expect(plan.fallbackProcessIDs.isEmpty)
        #expect(plan.matchedPIDs.isEmpty)
    }

    @Test
    func processListCommandUsesWidePsArguments() {
        let task = SystemProcessInspector.makeProcessListTask()

        #expect(task.executableURL?.path == "/bin/ps")
        #expect(task.arguments == ["-axww", "-o", "pid=,pgid=,command="])
    }

    @Test
    func commandLineLookupUsesWidePsArguments() {
        let task = SystemProcessInspector.makeCommandLineTask(pid: 1234)

        #expect(task.executableURL?.path == "/bin/ps")
        #expect(task.arguments == ["-p", "1234", "-ww", "-o", "command="])
    }

    @Test
    func parseProcessSnapshotsPreservesWidePsCommandLineOutput() {
        let output = """
        99751 99365 node /Users/test/Portlens/app/node_modules/next/dist/bin/next dev --hostname 0.0.0.0 --port 3000
        99767 99365 next-server (v15.5.18)
        """

        let snapshots = SystemProcessInspector.parseProcessSnapshots(
            from: output,
            currentWorkingDirectories: [
                99751: "/Users/test/Portlens/app",
                99767: "/Users/test/Portlens/app"
            ]
        )

        #expect(
            snapshots == [
                ProjectProcessSnapshot(
                    pid: 99751,
                    processGroupID: 99365,
                    commandLine: "node /Users/test/Portlens/app/node_modules/next/dist/bin/next dev --hostname 0.0.0.0 --port 3000",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                ),
                ProjectProcessSnapshot(
                    pid: 99767,
                    processGroupID: 99365,
                    commandLine: "next-server (v15.5.18)",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                )
            ]
        )
    }

    @Test
    func listeningTcpTasksAreConstructedBySystemInspector() {
        let scanTask = SystemProcessInspector.makeListeningTCPTask()
        let portTask = SystemProcessInspector.makeListeningPortTask(port: 3000)

        #expect(scanTask?.arguments == ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        #expect(portTask?.arguments == ["-i", ":3000", "-sTCP:LISTEN"])
    }
}

private struct ProcessSignalEvent: Equatable {
    let target: Int32
    let signal: Int32
}

private final class ProcessServiceStopRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var aliveProcessIDs: Set<Int32>
    private let processGroupIDs: [Int32: Int32]
    private let currentWorkingDirectories: [Int32: String]
    private let groupSignalSurvivors: Set<Int32>
    nonisolated(unsafe) private var recordedGroupSignals: [ProcessSignalEvent] = []
    nonisolated(unsafe) private var recordedProcessSignals: [ProcessSignalEvent] = []
    nonisolated(unsafe) private var snapshotScans = 0

    init(
        aliveProcessIDs: Set<Int32>,
        processGroupIDs: [Int32: Int32],
        currentWorkingDirectories: [Int32: String],
        groupSignalSurvivors: Set<Int32> = []
    ) {
        self.aliveProcessIDs = aliveProcessIDs
        self.processGroupIDs = processGroupIDs
        self.currentWorkingDirectories = currentWorkingDirectories
        self.groupSignalSurvivors = groupSignalSurvivors
    }

    nonisolated
    func recordSnapshotScan() {
        lock.lock()
        defer { lock.unlock() }
        snapshotScans += 1
    }

    nonisolated
    func snapshotScanCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshotScans
    }

    nonisolated
    func processGroupID(for pid: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return processGroupIDs[pid] ?? -1
    }

    nonisolated
    func isRunning(pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return aliveProcessIDs.contains(pid)
    }

    nonisolated
    func currentWorkingDirectory(for pid: Int32) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return currentWorkingDirectories[pid]
    }

    nonisolated
    func sendGroupSignal(groupID: Int32, signal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        recordedGroupSignals.append(ProcessSignalEvent(target: groupID, signal: signal))
        if signal == SIGTERM || signal == SIGKILL {
            aliveProcessIDs = Set(
                aliveProcessIDs.filter {
                    processGroupIDs[$0] != groupID || groupSignalSurvivors.contains($0)
                }
            )
        }
    }

    nonisolated
    func sendProcessSignal(pid: Int32, signal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        recordedProcessSignals.append(ProcessSignalEvent(target: pid, signal: signal))
        if signal == SIGTERM || signal == SIGKILL {
            aliveProcessIDs.remove(pid)
        }
    }

    nonisolated
    func groupSignals() -> [ProcessSignalEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedGroupSignals
    }

    nonisolated
    func processSignals() -> [ProcessSignalEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedProcessSignals
    }
}
