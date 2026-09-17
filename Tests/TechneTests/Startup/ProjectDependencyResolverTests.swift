import Foundation
import Testing
@testable import Techne

struct ProjectDependencyResolverTests {
    @Test
    func missingInstallArtifactsRequireInstall() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = makeProject(path: root.path)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project))
    }

    @Test
    func matchingSuccessfulFingerprintSkipsInstall() throws {
        let root = try makeProjectRoot(installedArtifact: "node_modules")
        defer { try? FileManager.default.removeItem(at: root) }
        let fingerprint = try #require(ProjectDependencyResolver.state(at: root.path).fingerprint)
        let project = makeProject(path: root.path, fingerprint: fingerprint)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project) == false)
    }

    @Test
    func changedManifestRequiresInstallAfterPreviousSuccess() throws {
        let root = try makeProjectRoot(installedArtifact: "node_modules")
        defer { try? FileManager.default.removeItem(at: root) }
        let fingerprint = try #require(ProjectDependencyResolver.state(at: root.path).fingerprint)
        var project = makeProject(path: root.path, fingerprint: fingerprint)

        try """
        {
          "dependencies": {
            "vue": "3.5.43"
          }
        }
        """.write(
            to: root.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project))
        project.preparedDependencyFingerprint = ProjectDependencyResolver.state(at: root.path).fingerprint
        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project) == false)
    }

    @Test
    func yarnPlugAndPlayArtifactCountsAsInstalled() throws {
        let root = try makeProjectRoot(
            installedArtifact: ".pnp.cjs",
            packageJSON: "{ \"packageManager\": \"yarn@4.9.2\" }",
            lockfile: "yarn.lock"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let project = makeProject(path: root.path)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project) == false)
    }

    @Test
    func workspaceLeafInstallsFromWorkspaceRoot() throws {
        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = workspaceRoot.appendingPathComponent("apps/web", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        try "{ \"packageManager\": \"pnpm@10.32.1\" }".write(
            to: workspaceRoot.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try "packages:\n  - apps/*".write(
            to: workspaceRoot.appendingPathComponent("pnpm-workspace.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try "lockfileVersion: '9.0'".write(
            to: workspaceRoot.appendingPathComponent("pnpm-lock.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try "{ \"scripts\": { \"dev\": \"vite\" } }".write(
            to: projectRoot.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let project = makeProject(path: projectRoot.path)
        let state = ProjectDependencyResolver.state(at: projectRoot.path)
        let plan = ProjectStartupCoordinator.makePlan(for: project, fallbackCleanCommand: "")

        #expect(state.workspaceRootPath == workspaceRoot.path)
        #expect(plan.phases.first == .install(
            command: "(cd \(ShellEscape.escape(workspaceRoot.path)) && pnpm install)"
        ))
    }

    private func makeProjectRoot(
        installedArtifact: String? = nil,
        packageJSON: String = "{}",
        lockfile: String = "pnpm-lock.yaml"
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try packageJSON.write(
            to: root.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try "lockfile".write(
            to: root.appendingPathComponent(lockfile),
            atomically: true,
            encoding: .utf8
        )
        if let installedArtifact {
            let artifactURL = root.appendingPathComponent(installedArtifact)
            if installedArtifact == "node_modules" {
                try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
            } else {
                try "".write(to: artifactURL, atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    private func makeProject(path: String, fingerprint: String? = nil) -> Project {
        Project(
            name: "frontend-app",
            path: path,
            type: .devServer,
            startCommand: "pnpm dev",
            installCommand: "pnpm install",
            installStrategy: .ifMissing,
            preparedDependencyFingerprint: fingerprint
        )
    }
}
