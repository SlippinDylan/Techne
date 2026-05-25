import Foundation
import Testing
@testable import DevNexus

@Suite(.serialized)
struct ProjectServiceStartupRecoveryTests {
    @Test
    @MainActor
    func stoppingDevServerAppendsTerminalHistoryAndClosesManagedBrowsers() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let projectRoot = isolatedPersistenceRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let browserStore = BrowserInstanceStore(rootDirectoryURL: isolatedPersistenceRoot.appendingPathComponent("browser-store"))
        let browserRecord = try makeBrowserRecord(
            store: browserStore,
            instanceName: "dev-server-browser",
            projectPath: projectRoot.path,
            port: 5173
        )
        let signalRecorder = TestManagedBrowserSignalRecorder(runningPIDs: [browserRecord.pid])
        let managedBrowserService = ManagedBrowserInstanceService(
            instanceStore: browserStore,
            sendSignal: signalRecorder.send(pid:signal:),
            isProcessRunning: signalRecorder.isRunning(pid:),
            sleep: { _ in }
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }
        let processService = makeProjectScopedTestProcessService(
            snapshots: [
                ProjectProcessSnapshot(
                    pid: process.processIdentifier,
                    processGroupID: getpgid(process.processIdentifier),
                    commandLine: "sleep 30",
                    currentWorkingDirectory: projectRoot.path
                )
            ]
        )

        let service = makeProjectService(
            persistenceRoot: isolatedPersistenceRoot,
            managedBrowserInstanceService: managedBrowserService,
            processService: processService
        )

        var project = Project(
            name: "stoppable-dev-server",
            path: projectRoot.path,
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev"
        )
        project.isRunning = true
        project.runningProcessPID = process.processIdentifier
        service.projects = [project]

        let result = await service.stopServer(for: project, cleanCache: false)

        guard case .success = result else {
            Issue.record("expected stopServer to succeed")
            return
        }

        let updatedProject = service.projects[0]
        #expect(updatedProject.isRunning == false)
        #expect(updatedProject.runningProcessPID == nil)
        #expect(updatedProject.transitionState == ProjectTransitionState.idle)
        #expect(updatedProject.terminalOutput.contains("[系统] 正在停止开发服务"))
        #expect(updatedProject.terminalOutput.contains("[系统] 开发服务已停止"))
        #expect(updatedProject.terminalOutput.contains("[系统] 检测到 1 个受管浏览器实例"))
        #expect(updatedProject.terminalOutput.contains("[系统] 已关闭浏览器实例 PID: \(browserRecord.pid)"))
        #expect(signalRecorder.events() == [ManagedSignalEvent(pid: browserRecord.pid, signal: SIGTERM)])
        #expect(try browserStore.loadTrackedInstances().isEmpty)
    }

    @Test
    @MainActor
    func installFailureResetsProjectBackToIdle() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let projectRoot = isolatedPersistenceRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let service = makeProjectService(persistenceRoot: isolatedPersistenceRoot)

        let project = Project(
            name: "broken-install-app",
            path: projectRoot.path,
            type: .devServer,
            startCommand: "touch start-ran",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "touch install-ran && false",
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: "Broken Install",
            installStrategy: .always
        )
        service.projects = [project]

        let result = service.startServer(for: project)

        guard case .success = result else {
            Issue.record("expected async startup to begin")
            return
        }

        let recovered = await waitUntil(timeout: .seconds(3)) {
            let updatedProject = service.projects[0]
            return updatedProject.transitionState == .idle
                && updatedProject.isRunning == false
                && updatedProject.runningProcessPID == nil
        }

        #expect(recovered)
        #expect(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("install-ran").path))
        #expect(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("start-ran").path) == false)
    }

    @Test
    @MainActor
    func cleanFailureDoesNotReachStartCommand() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let projectRoot = isolatedPersistenceRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let service = makeProjectService(persistenceRoot: isolatedPersistenceRoot)

        let project = Project(
            name: "broken-clean-app",
            path: projectRoot.path,
            type: .devServer,
            startCommand: "touch start-ran",
            buildCommand: "",
            cleanCommand: "touch clean-ran && false",
            installCommand: "",
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: "Broken Clean",
            installStrategy: .never
        )
        service.projects = [project]

        let result = service.startServer(for: project)

        guard case .success = result else {
            Issue.record("expected async startup to begin")
            return
        }

        let recovered = await waitUntil(timeout: .seconds(3)) {
            let updatedProject = service.projects[0]
            return updatedProject.transitionState == .idle
                && updatedProject.isRunning == false
                && updatedProject.runningProcessPID == nil
        }

        #expect(recovered)
        #expect(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("clean-ran").path))
        #expect(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("start-ran").path) == false)
    }

    @Test
    @MainActor
    func devServerDetectionNotificationWaitsUntilStartPhase() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let projectRoot = isolatedPersistenceRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let service = makeProjectService(persistenceRoot: isolatedPersistenceRoot)
        let project = Project(
            name: "delayed-dev-server",
            path: projectRoot.path,
            type: .devServer,
            startCommand: "sleep 0.2",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "sleep 0.4",
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: "Delayed Start",
            installStrategy: .always
        )
        service.projects = [project]

        let startedAt = ContinuousClock.now
        let recorder = NotificationRecorder(name: .devServerProcessStarted)
        defer { recorder.stop() }

        let result = service.startServer(for: project)

        guard case .success = result else {
            Issue.record("expected async startup to begin")
            return
        }

        try? await Task.sleep(for: .milliseconds(150))
        #expect(recorder.eventCount() == 0)

        let receivedNotification = await waitUntil(timeout: .seconds(3)) {
            recorder.eventCount() == 1
        }

        #expect(receivedNotification)

        let elapsed = recorder.firstEventElapsed(since: startedAt)
        #expect(elapsed >= .milliseconds(350))
    }

    @Test
    @MainActor
    func nestedDetectedServerClearsStartingStateForManagedRootProject() {
        let service = makeProjectService(
            persistenceRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        var project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev:mock"
        )
        project.transitionState = .starting
        service.projects = [project]

        let nestedServer = DevServer(
            id: 26834,
            processName: "node",
            port: 3000,
            projectPath: "/Users/test/Portlens/app",
            projectName: "app",
            serverType: .nextjs,
            commandLine: "node ./scripts/workspace-next.mjs dev mock"
        )

        service.reconcileDetectedDevServers([nestedServer])

        #expect(service.projects[0].runningProcessPID == 26834)
        #expect(service.projects[0].isRunning)
        #expect(service.projects[0].transitionState == .idle)
    }

    @Test
    @MainActor
    func stoppingDevServerUsesProjectRootScopeWhenStoredPIDIsStale() async {
        let persistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recorder = TestProcessRuntimeRecorder(
            aliveProcessIDs: [111, 99751, 99752, 99767],
            processGroupIDs: [
                111: 111,
                99751: 99365,
                99752: 99365,
                99767: 99365
            ]
        )
        let processService = ProcessService(
            runtime: .init(
                processSnapshots: {
                    [
                        ProjectProcessSnapshot(
                            pid: 111,
                            processGroupID: 111,
                            commandLine: "node /tmp/other-project/dev.mjs",
                            currentWorkingDirectory: "/tmp/other-project"
                        ),
                        ProjectProcessSnapshot(
                            pid: 99751,
                            processGroupID: 99365,
                            commandLine: "pnpm dev:mock",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        ProjectProcessSnapshot(
                            pid: 99752,
                            processGroupID: 99365,
                            commandLine: "node ./scripts/workspace-next.mjs dev mock",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        ProjectProcessSnapshot(
                            pid: 99767,
                            processGroupID: 99365,
                            commandLine: "next-server (v15.5.18)",
                            currentWorkingDirectory: "/Users/test/Portlens/app"
                        )
                    ]
                },
                processSnapshotForPID: {
                    let snapshotsByPID: [Int32: ProjectProcessSnapshot] = [
                        111: ProjectProcessSnapshot(
                            pid: 111,
                            processGroupID: 111,
                            commandLine: "node /tmp/other-project/dev.mjs",
                            currentWorkingDirectory: "/tmp/other-project"
                        ),
                        99751: ProjectProcessSnapshot(
                            pid: 99751,
                            processGroupID: 99365,
                            commandLine: "pnpm dev:mock",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        99752: ProjectProcessSnapshot(
                            pid: 99752,
                            processGroupID: 99365,
                            commandLine: "node ./scripts/workspace-next.mjs dev mock",
                            currentWorkingDirectory: "/Users/test/Portlens"
                        ),
                        99767: ProjectProcessSnapshot(
                            pid: 99767,
                            processGroupID: 99365,
                            commandLine: "next-server (v15.5.18)",
                            currentWorkingDirectory: "/Users/test/Portlens/app"
                        )
                    ]
                    return snapshotsByPID[$0]
                },
                processIDsInGroup: { processGroupID in
                    processGroupID == 99365 ? [99751, 99752, 99767] : [111]
                },
                processGroupID: recorder.processGroupID(for:),
                sendSignalToProcessGroup: recorder.sendGroupSignal(groupID:signal:),
                sendSignalToProcess: recorder.sendProcessSignal(pid:signal:),
                isProcessRunning: { pid in recorder.isRunning(pid: pid) },
                sleep: { _ in }
            )
        )
        let service = makeProjectService(
            persistenceRoot: persistenceRoot,
            managedBrowserInstanceService: ManagedBrowserInstanceService(),
            processService: processService
        )

        var project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev:mock"
        )
        project.isRunning = true
        project.runningProcessPID = 111
        service.projects = [project]

        let result = await service.stopServer(for: project, cleanCache: false)

        guard case .success = result else {
            Issue.record("expected stopServer to succeed when a descendant process matches the managed project root")
            return
        }

        let updatedProject = service.projects[0]
        #expect(updatedProject.runningProcessPID == nil)
        #expect(updatedProject.isRunning == false)
        #expect(updatedProject.transitionState == .idle)
        #expect(recorder.groupSignals() == [ProcessSignalEvent(target: 99365, signal: SIGTERM)])
        #expect(recorder.processSignals().isEmpty)
    }

    @Test
    @MainActor
    func switchingStartupModeWhileStoppedPersistsSelectionWithoutStartingProcess() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let service = makeProjectService(persistenceRoot: isolatedPersistenceRoot)
        let project = Project(
            name: "frontend-app",
            path: isolatedPersistenceRoot.appendingPathComponent("project").path,
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev",
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "pnpm dev", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "pnpm dev:mock", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )
        service.projects = [project]

        let result = await service.switchStartupMode(for: project, to: "dev:mock")

        guard case .success = result else {
            Issue.record("expected switchStartupMode to succeed")
            return
        }

        let updated = service.projects[0]
        #expect(updated.selectedStartupModeID == "dev:mock")
        #expect(updated.startCommand == "pnpm dev:mock")
        #expect(updated.isRunning == false)
    }

    @Test
    @MainActor
    func switchingStartupModeWhileRunningStopsOldProcessAndStartsNewCommand() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let projectRoot = isolatedPersistenceRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let oldProcess = Process()
        oldProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        oldProcess.arguments = ["30"]
        try oldProcess.run()
        defer {
            if oldProcess.isRunning {
                oldProcess.terminate()
            }
        }
        let processService = makeProjectScopedTestProcessService(
            snapshots: [
                ProjectProcessSnapshot(
                    pid: oldProcess.processIdentifier,
                    processGroupID: getpgid(oldProcess.processIdentifier),
                    commandLine: "sleep 30",
                    currentWorkingDirectory: projectRoot.path
                )
            ]
        )

        let service = makeProjectService(
            persistenceRoot: isolatedPersistenceRoot,
            managedBrowserInstanceService: ManagedBrowserInstanceService(),
            processService: processService
        )
        var project = Project(
            name: "portlens-workspace",
            path: projectRoot.path,
            type: .devServer,
            currentBranch: "main",
            startCommand: "sleep 30",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "",
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Next.js + pnpm",
            installStrategy: .never,
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "sleep 30", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "touch mode-switched && sleep 0.2", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )
        project.isRunning = true
        project.runningProcessPID = oldProcess.processIdentifier
        service.projects = [project]

        let result = await service.switchStartupMode(for: project, to: "dev:mock")

        guard case .success = result else {
            Issue.record("expected switchStartupMode to begin restart")
            return
        }

        let restarted = await waitUntil(timeout: .seconds(3)) {
            FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("mode-switched").path)
        }

        #expect(restarted)
        #expect(service.projects[0].selectedStartupModeID == "dev:mock")
        #expect(service.projects[0].startCommand == "touch mode-switched && sleep 0.2")
        #expect(service.projects[0].terminalOutput.contains("[系统] 已切换启动模式为 Mock"))
    }

    @MainActor
    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(50),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }

        return condition()
    }

    @MainActor
    private func makeProjectService(persistenceRoot: URL) -> ProjectService {
        makeProjectService(
            persistenceRoot: persistenceRoot,
            managedBrowserInstanceService: ManagedBrowserInstanceService(),
            processService: makeDefaultTestProcessService()
        )
    }

    @MainActor
    private func makeProjectService(
        persistenceRoot: URL,
        managedBrowserInstanceService: ManagedBrowserInstanceService,
        processService: ProcessService? = nil
    ) -> ProjectService {
        let configService = CommandConfigService(
            persistenceService: PersistenceService<CommandConfig>(
                filename: "commandconfigs.json",
                root: .custom(persistenceRoot)
            )
        )
        let resolvedProcessService = processService ?? makeDefaultTestProcessService()

        return ProjectService(
            commandConfigService: configService,
            processService: resolvedProcessService,
            managedBrowserInstanceService: managedBrowserInstanceService,
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                root: .custom(persistenceRoot)
            )
        )
    }

    private func makeDefaultTestProcessService() -> ProcessService {
        ProcessService(
            runtime: .init(
                processSnapshots: { [] },
                processSnapshotForPID: { _ in nil },
                processIDsInGroup: { _ in [] },
                processGroupID: { pid in getpgid(pid) },
                sendSignalToProcessGroup: { processGroupID, signal in
                    kill(-processGroupID, signal)
                },
                sendSignalToProcess: { pid, signal in
                    kill(pid, signal)
                },
                isProcessRunning: { pid in
                    kill(pid, 0) == 0
                },
                sleep: { nanoseconds in
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
            )
        )
    }

    private func makeProjectScopedTestProcessService(
        snapshots: [ProjectProcessSnapshot]
    ) -> ProcessService {
        let snapshotsByPID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0) })
        let processGroupMemberPIDs = Dictionary(grouping: snapshots, by: \.processGroupID)
            .mapValues { groupSnapshots in
                groupSnapshots.map(\.pid)
            }
        return ProcessService(
            runtime: .init(
                processSnapshots: { snapshots },
                processSnapshotForPID: { pid in
                    snapshotsByPID[pid]
                },
                processIDsInGroup: { processGroupID in
                    processGroupMemberPIDs[processGroupID] ?? []
                },
                processGroupID: { pid in getpgid(pid) },
                sendSignalToProcessGroup: { processGroupID, signal in
                    kill(-processGroupID, signal)
                },
                sendSignalToProcess: { pid, signal in
                    kill(pid, signal)
                },
                isProcessRunning: { pid in
                    kill(pid, 0) == 0
                },
                sleep: { nanoseconds in
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
            )
        )
    }

    private func makeBrowserRecord(
        store: BrowserInstanceStore,
        instanceName: String,
        projectPath: String,
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

private final class TestManagedBrowserSignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var runningPIDs: Set<Int32>
    nonisolated(unsafe) private(set) var signals: [ManagedSignalEvent] = []

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

        signals.append(ManagedSignalEvent(pid: pid, signal: signal))

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

    nonisolated
    func events() -> [ManagedSignalEvent] {
        lock.lock()
        defer { lock.unlock() }
        return signals
    }
}

private struct ManagedSignalEvent: Equatable {
    let pid: Int32
    let signal: Int32
}

private struct ProcessSignalEvent: Equatable {
    let target: Int32
    let signal: Int32
}

private final class TestProcessRuntimeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var aliveProcessIDs: Set<Int32>
    private let processGroupIDs: [Int32: Int32]
    nonisolated(unsafe) private var recordedGroupSignals: [ProcessSignalEvent] = []
    nonisolated(unsafe) private var recordedProcessSignals: [ProcessSignalEvent] = []

    init(aliveProcessIDs: Set<Int32>, processGroupIDs: [Int32: Int32]) {
        self.aliveProcessIDs = aliveProcessIDs
        self.processGroupIDs = processGroupIDs
    }

    nonisolated
    func processGroupID(for pid: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return processGroupIDs[pid] ?? -1
    }

    nonisolated
    func sendGroupSignal(groupID: Int32, signal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        recordedGroupSignals.append(ProcessSignalEvent(target: groupID, signal: signal))
        if signal == SIGTERM || signal == SIGKILL {
            aliveProcessIDs = Set(aliveProcessIDs.filter { processGroupIDs[$0] != groupID })
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
    func isRunning(pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return aliveProcessIDs.contains(pid)
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

private final class NotificationRecorder: @unchecked Sendable {
    private let center: NotificationCenter
    private let lock = NSLock()
    nonisolated(unsafe) private var timestamps: [ContinuousClock.Instant] = []
    nonisolated(unsafe) private var token: NSObjectProtocol?

    nonisolated
    init(name: Notification.Name, center: NotificationCenter = .default) {
        self.center = center
        self.token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            self?.record()
        }
    }

    nonisolated
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let token {
            center.removeObserver(token)
            self.token = nil
        }
    }

    nonisolated
    func eventCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return timestamps.count
    }

    nonisolated
    func firstEventElapsed(since start: ContinuousClock.Instant) -> Duration {
        lock.lock()
        defer { lock.unlock() }
        guard let first = timestamps.first else { return .zero }
        return start.duration(to: first)
    }

    nonisolated
    private func record() {
        lock.lock()
        defer { lock.unlock() }
        timestamps.append(ContinuousClock.now)
    }
}
