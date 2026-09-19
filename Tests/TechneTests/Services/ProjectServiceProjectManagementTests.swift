import Foundation
import Testing
@testable import Techne

struct ProjectServiceProjectManagementTests {
    @Test
    @MainActor
    func addProjectStoresCanonicalPathAndRejectsSymlinkAlias() throws {
        let fixtureRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".techne-test-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let realProjectURL = fixtureRoot.appendingPathComponent("real-project", isDirectory: true)
        let symlinkProjectURL = fixtureRoot.appendingPathComponent("project-link", isDirectory: false)
        let persistenceRoot = fixtureRoot.appendingPathComponent("persistence", isDirectory: true)
        try FileManager.default.createDirectory(at: realProjectURL, withIntermediateDirectories: true)
        try """
        {
          "scripts": {
            "dev": "vite"
          },
          "devDependencies": {
            "vite": "7.2.4"
          }
        }
        """.write(
            to: realProjectURL.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: symlinkProjectURL,
            withDestinationURL: realProjectURL
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let service = makeProjectService(persistenceRoot: persistenceRoot)

        let firstResult = service.addProject(path: symlinkProjectURL.path, type: .devServer)
        guard case .success(let project) = firstResult else {
            Issue.record("expected the symlink path to add successfully")
            return
        }

        #expect(project.path == realProjectURL.path)
        #expect(service.projects.map(\.path) == [realProjectURL.path])

        let duplicateResult = service.addProject(path: realProjectURL.path + "/", type: .devServer)
        guard case .failure(.projectAlreadyExists(let duplicatePath)) = duplicateResult else {
            Issue.record("expected the canonical path alias to be rejected as a duplicate")
            return
        }

        #expect(duplicatePath == realProjectURL.path)
        #expect(service.projects.count == 1)
    }

    @Test
    @MainActor
    func addProjectRejectsDirectoryWithoutRunnableManifest() throws {
        let fixtureRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".techne-test-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectURL = fixtureRoot.appendingPathComponent("documentation-only", isDirectory: true)
        let persistenceRoot = fixtureRoot.appendingPathComponent("persistence", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let service = makeProjectService(persistenceRoot: persistenceRoot)
        let result = service.addProject(path: projectURL.path, type: .miniApp)

        guard case .failure(.invalidConfiguration(let reason)) = result else {
            Issue.record("expected a documentation-only directory to be rejected")
            return
        }

        #expect(reason.contains("package.json"))
        #expect(service.projects.isEmpty)
    }

    @Test
    @MainActor
    func explicitCommandConfigAllowsNonstandardProject() throws {
        let fixtureRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".techne-test-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectURL = fixtureRoot.appendingPathComponent("nonstandard-project", isDirectory: true)
        let persistenceRoot = fixtureRoot.appendingPathComponent("persistence", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let config = CommandConfig(
            name: "Custom runner",
            projectType: .devServer,
            startCommand: "custom-tool watch"
        )
        let service = makeProjectService(persistenceRoot: persistenceRoot, commandConfig: config)

        let result = service.addProject(path: projectURL.path, type: .devServer, configId: config.id)

        guard case .success(let project) = result else {
            Issue.record("expected an explicit command config to define a nonstandard project")
            return
        }
        #expect(project.startCommand == "custom-tool watch")
        #expect(project.commandConfigId == config.id)
    }

    @Test
    @MainActor
    func missingCommandConfigIsRejected() throws {
        let fixtureRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".techne-test-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectURL = fixtureRoot.appendingPathComponent("project", isDirectory: true)
        let persistenceRoot = fixtureRoot.appendingPathComponent("persistence", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let service = makeProjectService(persistenceRoot: persistenceRoot)
        let result = service.addProject(path: projectURL.path, type: .devServer, configId: UUID())

        guard case .failure(.invalidConfiguration(let reason)) = result else {
            Issue.record("expected an unknown command config to be rejected")
            return
        }
        #expect(reason == AppLocalized("error.project.selected_command_configuration_not_found"))
    }

    @MainActor
    private func makeProjectService(
        persistenceRoot: URL,
        commandConfig: CommandConfig? = nil
    ) -> ProjectService {
        let commandConfigService = CommandConfigService(
            persistenceService: PersistenceService<CommandConfig>(
                filename: "commandconfigs.json",
                root: .custom(persistenceRoot)
            )
        )
        if let commandConfig {
            _ = commandConfigService.addConfig(commandConfig)
        }
        return ProjectService(
            commandConfigService: commandConfigService,
            persistenceService: PersistenceService<Project>(
                filename: "projects.json",
                root: .custom(persistenceRoot)
            ),
            startupBehavior: .empty
        )
    }
}
