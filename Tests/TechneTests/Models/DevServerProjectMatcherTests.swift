import Foundation
import Testing
@testable import Techne

struct DevServerProjectMatcherTests {
    @Test
    func descendantServerPathMatchesAncestorManagedProject() {
        let projectPath = "/Users/test/Portlens"
        let server = makeServer(
            id: 26834,
            path: "/Users/test/Portlens/app",
            port: 3000
        )

        #expect(
            DevServerProjectMatcher.belongs(serverPath: server.projectPath, toProjectPath: projectPath)
        )
    }

    @Test
    func unrelatedSiblingPathDoesNotMatchManagedProject() {
        #expect(
            DevServerProjectMatcher.belongs(
                serverPath: "/Users/test/Portlens-docs/app",
                toProjectPath: "/Users/test/Portlens"
            ) == false
        )
    }

    @Test
    func bestMatchingProjectPrefersMostSpecificManagedAncestor() {
        let server = makeServer(
            id: 3001,
            path: "/Users/test/Portlens/app",
            port: 3001
        )

        let bestMatch = DevServerProjectMatcher.bestMatchingProjectPath(
            for: server,
            managedProjectPaths: [
                "/Users/test/Portlens",
                "/Users/test/Portlens/app"
            ]
        )

        #expect(bestMatch == "/Users/test/Portlens/app")
    }

    @Test
    func unmanagedServersExcludeNestedPathsOwnedByManagedProjects() {
        let managedPaths = [
            "/Users/test/blog",
            "/Users/test/Portlens"
        ]

        let servers = [
            makeServer(
                id: 13650,
                path: "/Users/test/Portlens/app",
                port: 3000
            ),
            makeServer(
                id: 22724,
                path: "/Users/test/elsewhere/demo",
                port: 3001
            )
        ]

        let unmanaged = servers.filter { server in
            DevServerProjectMatcher.bestMatchingProjectPath(
                for: server,
                managedProjectPaths: managedPaths
            ) == nil
        }

        #expect(unmanaged.map(\.id) == [22724])
    }

    private func makeServer(id: Int32, path: String, port: Int) -> DevServer {
        DevServer(
            id: id,
            processName: "node",
            port: port,
            projectPath: path,
            projectName: URL(fileURLWithPath: path).lastPathComponent,
            serverType: .nextjs,
            commandLine: "node ./scripts/workspace-next.mjs dev mock"
        )
    }
}
