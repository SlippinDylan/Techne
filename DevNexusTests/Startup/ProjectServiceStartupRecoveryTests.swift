import Foundation
import Testing
@testable import DevNexus

struct ProjectServiceStartupRecoveryTests {
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
        let configService = CommandConfigService(
            persistenceService: PersistenceService<CommandConfig>(
                filename: "commandconfigs.json",
                directoryURL: persistenceRoot
            )
        )

        return ProjectService(
            commandConfigService: configService,
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                directoryURL: persistenceRoot
            )
        )
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
