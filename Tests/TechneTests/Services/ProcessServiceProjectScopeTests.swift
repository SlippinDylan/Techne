import Foundation
import Testing
@testable import Techne

struct ProcessServiceProjectScopeTests {
    @Test
    func matchingRuntimeCommandStopsItsProcessGroup() async {
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
                    return [
                        ProjectProcessSnapshot(
                            pid: 99752,
                            processGroupID: 99365,
                            commandLine: "pnpm dev:mock",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        ProjectProcessSnapshot(
                            pid: 99767,
                            processGroupID: 99365,
                            commandLine: "next-server",
                            currentWorkingDirectory: "/Users/test/Portlens/app"
                        )
                    ]
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

        let project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            startCommand: "pnpm dev:mock"
        )
        let result = await service.stopProjectProcesses(for: project)

        guard case .success = result else {
            Issue.record("expected preferred PID stop to succeed")
            return
        }

        #expect(recorder.snapshotScanCount() == 1)
        #expect(recorder.groupSignals() == [ProcessSignalEvent(target: 99365, signal: SIGINT)])
        #expect(recorder.processSignals().isEmpty)
    }

    @Test
    func matchingRuntimeGroupFailureEscalatesSignals() async {
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
                    return [
                        ProjectProcessSnapshot(
                            pid: 99752,
                            processGroupID: 99365,
                            commandLine: "pnpm dev:mock",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        ProjectProcessSnapshot(
                            pid: 99767,
                            processGroupID: 99365,
                            commandLine: "next-server",
                            currentWorkingDirectory: "/Users/test/Portlens/app"
                        )
                    ]
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

        let project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            startCommand: "pnpm dev:mock"
        )
        let result = await service.stopProjectProcesses(for: project)

        guard case .failure = result else {
            Issue.record("expected stop to fail when a sibling process survives both group signals")
            return
        }

        #expect(recorder.snapshotScanCount() == 1)
        #expect(recorder.groupSignals() == [
            ProcessSignalEvent(target: 99365, signal: SIGINT),
            ProcessSignalEvent(target: 99365, signal: SIGTERM),
            ProcessSignalEvent(target: 99365, signal: SIGKILL)
        ])
    }

    @Test
    func hostProcessGroupSignalsOnlyProjectScopedMembers() async {
        let preferredPID: Int32 = 99752
        let unrelatedPID: Int32 = 99767
        let hostProcessGroup = getpgrp()
        let recorder = ProcessServiceStopRecorder(
            aliveProcessIDs: [preferredPID, unrelatedPID],
            processGroupIDs: [
                preferredPID: hostProcessGroup,
                unrelatedPID: hostProcessGroup
            ],
            currentWorkingDirectories: [
                preferredPID: "/Users/test/Portlens",
                unrelatedPID: "/Users/test/other-project"
            ]
        )
        let service = ProcessService(
            runtime: .init(
                processSnapshots: {
                    [
                        ProjectProcessSnapshot(
                            pid: preferredPID,
                            processGroupID: hostProcessGroup,
                            commandLine: "pnpm dev",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        ProjectProcessSnapshot(
                            pid: unrelatedPID,
                            processGroupID: hostProcessGroup,
                            commandLine: "pnpm dev",
                            currentWorkingDirectory: "/Users/test/other-project"
                        )
                    ]
                },
                processSnapshotForPID: { pid in
                    ProjectProcessSnapshot(
                        pid: pid,
                        processGroupID: recorder.processGroupID(for: pid),
                        commandLine: "pnpm dev",
                        currentWorkingDirectory: recorder.currentWorkingDirectory(for: pid)
                    )
                },
                processIDsInGroup: { _ in [preferredPID, unrelatedPID] },
                processGroupID: recorder.processGroupID(for:),
                sendSignalToProcessGroup: recorder.sendGroupSignal(groupID:signal:),
                sendSignalToProcess: recorder.sendProcessSignal(pid:signal:),
                isProcessRunning: { pid in recorder.isRunning(pid: pid) },
                sleep: { _ in }
            )
        )

        let project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            startCommand: "pnpm dev"
        )
        let result = await service.stopProjectProcesses(for: project)

        guard case .success = result else {
            Issue.record("expected a safe single-process fallback")
            return
        }
        #expect(recorder.groupSignals().isEmpty)
        #expect(recorder.processSignals() == [
            ProcessSignalEvent(target: preferredPID, signal: SIGINT)
        ])
        #expect(recorder.isRunning(pid: unrelatedPID))
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
            ProjectProcessScope.contains(
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
            ProjectProcessScope.contains(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            )
        )
    }

    @Test
    func unrelatedWorkingDirectoryOverridesEnvironmentPathMention() {
        let process = ProjectProcessSnapshot(
            pid: 99752,
            processGroupID: 99365,
            commandLine: "external-tool INIT_CWD=/Users/test/Portlens",
            currentWorkingDirectory: "/Users/test/other-project"
        )

        #expect(
            ProjectProcessScope.contains(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            ) == false
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
            ProjectProcessScope.contains(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            ) == false
        )
    }

    @Test
    func stopIgnoresTerminalCodexAndUnrelatedNPMProcessesInProjectDirectory() async {
        let project = Project(
            name: "staff-miniapp",
            path: "/Users/test/staff-miniapp",
            type: .miniApp,
            startCommand: "pnpm dev:weapp"
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 100,
                processGroupID: 100,
                commandLine: "-/bin/zsh",
                currentWorkingDirectory: project.path
            ),
            ProjectProcessSnapshot(
                pid: 200,
                processGroupID: 200,
                commandLine: "node /usr/local/bin/codex",
                currentWorkingDirectory: project.path
            ),
            ProjectProcessSnapshot(
                pid: 300,
                processGroupID: 300,
                commandLine: "npm exec context7-mcp",
                currentWorkingDirectory: project.path
            ),
            ProjectProcessSnapshot(
                pid: 400,
                processGroupID: 400,
                commandLine: "node /opt/pnpm dev:weapp",
                currentWorkingDirectory: project.path
            ),
            ProjectProcessSnapshot(
                pid: 401,
                processGroupID: 400,
                commandLine: "node ./node_modules/@tarojs/cli/bin/taro build --watch",
                currentWorkingDirectory: project.path
            )
        ]
        let recorder = ProcessServiceStopRecorder(
            aliveProcessIDs: Set(snapshots.map(\.pid)),
            processGroupIDs: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0.processGroupID) }),
            currentWorkingDirectories: Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot in
                snapshot.currentWorkingDirectory.map { (snapshot.pid, $0) }
            })
        )
        let service = ProcessService(
            runtime: .init(
                processSnapshots: { snapshots },
                processSnapshotForPID: { _ in nil },
                processIDsInGroup: { groupID in groupID == 400 ? [400, 401] : [] },
                processGroupID: recorder.processGroupID(for:),
                sendSignalToProcessGroup: recorder.sendGroupSignal(groupID:signal:),
                sendSignalToProcess: recorder.sendProcessSignal(pid:signal:),
                isProcessRunning: { pid in recorder.isRunning(pid: pid) },
                sleep: { _ in }
            )
        )

        let result = await service.stopAllProjectProcessesIfPresent(for: project)

        guard case .success(.stopped) = result else {
            Issue.record("expected only the matching development service to stop")
            return
        }
        #expect(recorder.groupSignals() == [ProcessSignalEvent(target: 400, signal: SIGINT)])
        #expect(recorder.isRunning(pid: 100))
        #expect(recorder.isRunning(pid: 200))
        #expect(recorder.isRunning(pid: 300))
    }

    @Test
    func stopReturnsNotFoundWhenOnlyUnrelatedProjectProcessesExist() async {
        let project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            startCommand: "pnpm dev"
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 111,
                processGroupID: 111,
                commandLine: "node /usr/local/bin/codex",
                currentWorkingDirectory: project.path
            ),
            ProjectProcessSnapshot(
                pid: 222,
                processGroupID: 222,
                commandLine: "npm exec context7-mcp",
                currentWorkingDirectory: project.path
            )
        ]
        let recorder = ProcessServiceStopRecorder(
            aliveProcessIDs: Set(snapshots.map(\.pid)),
            processGroupIDs: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0.processGroupID) }),
            currentWorkingDirectories: Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot in
                snapshot.currentWorkingDirectory.map { (snapshot.pid, $0) }
            })
        )
        let service = ProcessService(
            runtime: .init(
                processSnapshots: { snapshots },
                processSnapshotForPID: { _ in nil },
                processIDsInGroup: { _ in [] },
                processGroupID: recorder.processGroupID(for:),
                sendSignalToProcessGroup: recorder.sendGroupSignal(groupID:signal:),
                sendSignalToProcess: recorder.sendProcessSignal(pid:signal:),
                isProcessRunning: { pid in recorder.isRunning(pid: pid) },
                sleep: { _ in }
            )
        )

        let result = await service.stopAllProjectProcessesIfPresent(for: project)

        guard case .success(.notFound) = result else {
            Issue.record("expected unrelated project-directory processes to be ignored")
            return
        }
        #expect(recorder.groupSignals().isEmpty)
        #expect(recorder.processSignals().isEmpty)
    }

    @Test
    func projectScopeIgnoresUnrelatedStoredPID() {
        let process = ProjectProcessSnapshot(
            pid: 111,
            processGroupID: 111,
            commandLine: "node /tmp/other-project/dev.mjs",
            currentWorkingDirectory: "/tmp/other-project"
        )

        #expect(ProjectProcessScope.contains(
            process: process,
            projectRootPath: "/Users/test/Portlens"
        ) == false)
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
        if signal == SIGINT || signal == SIGTERM || signal == SIGKILL {
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
        if signal == SIGINT || signal == SIGTERM || signal == SIGKILL {
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
