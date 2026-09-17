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
        try "#!/bin/sh\nexit 0\n".write(to: cli, atomically: true, encoding: .utf8)
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
}
