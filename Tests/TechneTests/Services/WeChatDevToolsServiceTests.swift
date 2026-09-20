import Foundation
import Testing
@testable import Techne

struct WeChatDevToolsServiceTests {
    @Test
    func resetPlanUsesInstalledCLIAndRootProjectConfiguration() throws {
        let fixture = try makeFixture(configurationRelativePath: "project.config.json")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = WeChatDevToolsService(applicationDirectories: [fixture.applications])

        let plan = try service.makeResetPlan(for: fixture.project.path).get()

        #expect(plan.executableURL.path == fixture.cli.path)
        #expect(plan.arguments == ["reset-fileutils", "--project", fixture.project.path])
    }

    @Test
    func resetPlanFindsGeneratedUniAppProjectConfiguration() throws {
        let fixture = try makeFixture(
            configurationRelativePath: "unpackage/dist/dev/mp-weixin/project.config.json"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = WeChatDevToolsService(applicationDirectories: [fixture.applications])

        let plan = try service.makeResetPlan(for: fixture.project.path).get()

        #expect(plan.projectPath == fixture.project.appendingPathComponent("unpackage/dist/dev/mp-weixin").path)
    }

    @Test
    func resetPlanRejectsDirectoryWithoutProjectConfiguration() throws {
        let fixture = try makeFixture(configurationRelativePath: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = WeChatDevToolsService(applicationDirectories: [fixture.applications])

        let result = service.makeResetPlan(for: fixture.project.path)

        guard case .failure(.projectConfigurationNotFound) = result else {
            Issue.record("expected missing project configuration failure")
            return
        }
    }

    @Test
    func openAndCloseUseDeveloperToolsProjectCommands() async throws {
        let fixture = try makeFixture(configurationRelativePath: "project.config.json")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = WeChatDevToolsService(applicationDirectories: [fixture.applications])

        let openOutput = try await service.openProject(at: fixture.project.path).get()
        let closeOutput = try await service.closeProject(at: fixture.project.path).get()

        #expect(openOutput == "open --project \(fixture.project.path)")
        #expect(closeOutput == "close --project \(fixture.project.path)")
    }

    @Test
    @MainActor
    func nativeProjectServiceTracksDeveloperToolsOpenAndClose() async throws {
        let fixture = try makeFixture(configurationRelativePath: "project.config.json")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = ProjectService(
            commandConfigService: CommandConfigService(
                persistenceService: PersistenceService<CommandConfig>(
                    filename: "commandconfigs.json",
                    root: .custom(fixture.root)
                )
            ),
            weChatDevToolsService: WeChatDevToolsService(applicationDirectories: [fixture.applications]),
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                root: .custom(fixture.root)
            ),
            startupBehavior: .empty
        )
        let project = Project(
            name: "native-mini-app",
            path: fixture.project.path,
            type: .miniApp,
            commandProfileName: "自动识别 · 原生微信小程序",
            installStrategy: .never,
            runtimeKind: .weChatNative
        )
        service.projects = [project]

        _ = try service.startServer(for: project).get()
        let didOpen = await waitUntil { service.projects[0].transitionState == .idle }

        #expect(didOpen)
        #expect(service.projects[0].isRunning)
        #expect(service.projects[0].terminalOutput.contains("open --project"))

        _ = try await service.stopServer(for: service.projects[0]).get()

        #expect(service.projects[0].isRunning == false)
        #expect(service.projects[0].terminalOutput.contains("close --project"))
    }

    @Test
    @MainActor
    func nativeReplaceAndStartClosesProjectBeforeOpeningIt() async throws {
        let fixture = try makeFixture(configurationRelativePath: "project.config.json")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let commandLog = fixture.root.appendingPathComponent("commands.log")
        try """
        #!/bin/sh
        printf '%s\n' "$*" >> "\(commandLog.path)"
        printf '%s\n' "$*"
        """.write(to: fixture.cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.cli.path
        )
        let service = ProjectService(
            commandConfigService: CommandConfigService(
                persistenceService: PersistenceService<CommandConfig>(
                    filename: "commandconfigs.json",
                    root: .custom(fixture.root)
                )
            ),
            weChatDevToolsService: WeChatDevToolsService(applicationDirectories: [fixture.applications]),
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                root: .custom(fixture.root)
            ),
            startupBehavior: .empty
        )
        let project = Project(
            name: "native-mini-app",
            path: fixture.project.path,
            type: .miniApp,
            runtimeKind: .weChatNative
        )
        service.projects = [project]

        _ = try await service.replaceAndStartServer(for: project).get()
        let didOpen = await waitUntil { service.projects[0].transitionState == .idle }
        let commands = try String(contentsOf: commandLog, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        #expect(didOpen)
        #expect(commands == [
            "close --project \(fixture.project.path)",
            "open --project \(fixture.project.path)"
        ])
    }

    @Test
    @MainActor
    func nativeShutdownLeavesDeveloperToolsProjectOpen() async throws {
        let fixture = try makeFixture(configurationRelativePath: "project.config.json")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try "#!/bin/sh\nprintf 'unexpected invocation' 1>&2\nexit 1\n".write(
            to: fixture.cli,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.cli.path
        )
        let service = ProjectService(
            commandConfigService: CommandConfigService(
                persistenceService: PersistenceService<CommandConfig>(
                    filename: "commandconfigs.json",
                    root: .custom(fixture.root)
                )
            ),
            weChatDevToolsService: WeChatDevToolsService(applicationDirectories: [fixture.applications]),
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                root: .custom(fixture.root)
            ),
            startupBehavior: .empty
        )
        var project = Project(
            name: "native-mini-app",
            path: fixture.project.path,
            type: .miniApp,
            runtimeKind: .weChatNative
        )
        project.isRunning = true
        service.projects = [project]

        let failures = await service.shutdownAllProjects()

        #expect(failures.isEmpty)
        #expect(service.isShuttingDown)
    }

    private func makeFixture(
        configurationRelativePath: String?
    ) throws -> (root: URL, applications: URL, project: URL, cli: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let app = applications.appendingPathComponent("wechatwebdevtools.app", isDirectory: true)
        let cli = app.appendingPathComponent("Contents/MacOS/cli")
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cli.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nprintf '%s\\n' \"$*\"\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: cli.path
        )
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        if let configurationRelativePath {
            let configurationURL = project.appendingPathComponent(configurationRelativePath)
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try """
            {
              "appid": "wx-test",
              "projectname": "test-project"
            }
            """.write(to: configurationURL, atomically: true, encoding: .utf8)
        }

        return (root, applications, project, cli)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
