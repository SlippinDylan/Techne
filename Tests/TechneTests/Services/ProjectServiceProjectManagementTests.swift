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

    @MainActor
    private func makeProjectService(persistenceRoot: URL) -> ProjectService {
        let commandConfigService = CommandConfigService(
            persistenceService: PersistenceService<CommandConfig>(
                filename: "commandconfigs.json",
                root: .custom(persistenceRoot)
            )
        )
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
