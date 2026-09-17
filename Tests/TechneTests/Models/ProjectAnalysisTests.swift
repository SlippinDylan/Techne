import Foundation
import Testing
@testable import Techne

struct ProjectAnalysisTests {
    @Test
    func taroProjectUsesDeclaredWeappScripts() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "packageManager": "pnpm@10.32.1",
              "scripts": {
                "dev:weapp": "taro build --type weapp --watch",
                "build:weapp": "taro build --type weapp"
              },
              "devDependencies": {
                "@tarojs/cli": "4.2.1"
              }
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let result = ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .miniApp,
            path: projectRoot.path
        )
        let snapshot = try result.get()

        #expect(snapshot.startCommand == "pnpm dev:weapp")
        #expect(snapshot.buildCommand == "pnpm build:weapp")
        #expect(snapshot.cleanCommand.isEmpty)
        #expect(snapshot.commandProfileName == "自动识别 · Taro + pnpm")
    }

    @Test
    func mpxProjectUsesServeAndBuildScripts() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "scripts": {
                "serve": "mpx-cli-service serve",
                "build": "mpx-cli-service build"
              },
              "dependencies": {
                "@mpxjs/core": "2.11.1"
              }
            }
            """,
            lockfile: "package-lock.json"
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let snapshot = try ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .miniApp,
            path: projectRoot.path
        ).get()

        #expect(snapshot.startCommand == "npm run serve")
        #expect(snapshot.buildCommand == "npm run build")
        #expect(snapshot.commandProfileName == "自动识别 · Mpx + npm")
    }

    @Test
    func uniAppProjectUsesWeChatScriptsAndModes() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "packageManager": "pnpm@10.10.0",
              "scripts": {
                "dev": "uni",
                "dev:mp": "uni -p mp-weixin",
                "dev:mp:zonowry": "uni -p mp-weixin --mode zonowry",
                "dev:mp-weixin": "uni -p mp-weixin",
                "build:mp-weixin": "uni build -p mp-weixin"
              },
              "dependencies": {
                "@dcloudio/uni-app": "3.0.0"
              }
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let snapshot = try ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .miniApp,
            path: projectRoot.path
        ).get()

        #expect(snapshot.startCommand == "pnpm dev:mp-weixin")
        #expect(snapshot.startupModes.map(\.id) == ["dev:mp-weixin", "dev:mp", "dev:mp:zonowry"])
        #expect(snapshot.buildCommand == "pnpm build:mp-weixin")
        #expect(snapshot.commandProfileName == "自动识别 · UniApp + pnpm")
    }

    @Test
    func webProjectIncludesEveryDeclaredDevMode() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "scripts": {
                "dev": "vite",
                "dev:live": "vite --mode live",
                "dev:zonowry": "vite --mode zonowry",
                "build": "vite build"
              },
              "devDependencies": {
                "vite": "7.2.4"
              }
            }
            """,
            lockfile: "pnpm-lock.yaml"
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let snapshot = try ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .devServer,
            path: projectRoot.path
        ).get()

        #expect(snapshot.startupModes.map(\.id) == ["dev", "dev:live", "dev:zonowry"])
        #expect(snapshot.startCommand == "pnpm dev")
    }

    @Test
    func nodeProjectWithoutPackageManagerMetadataDefaultsToNpm() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "scripts": {
                "dev": "custom-dev-server"
              }
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let snapshot = try ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .devServer,
            path: projectRoot.path
        ).get()

        #expect(snapshot.startCommand == "npm run dev")
        #expect(snapshot.installCommand == "npm install")
    }

    @Test
    func directoryWithoutPackageManifestIsRejected() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let result = ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .miniApp,
            path: projectRoot.path
        )

        guard case .failure(.missingPackageManifest) = result else {
            Issue.record("expected a directory without package.json to be rejected")
            return
        }
    }

    @Test
    func malformedPackageManifestIsRejected() throws {
        let projectRoot = try makeProject(packageJSON: "{ not-json }")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let result = ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .devServer,
            path: projectRoot.path
        )

        guard case .failure(.invalidPackageManifest) = result else {
            Issue.record("expected malformed package.json to be rejected")
            return
        }
    }

    @Test
    func projectWithoutRunnableScriptIsRejected() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "scripts": {
                "lint": "eslint ."
              }
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let result = ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .devServer,
            path: projectRoot.path
        )

        guard case .failure(.missingDevelopmentScript(.devServer)) = result else {
            Issue.record("expected a project without a development script to be rejected")
            return
        }
    }

    @Test
    func projectWithBlankDevelopmentScriptIsRejected() throws {
        let projectRoot = try makeProject(
            packageJSON: """
            {
              "scripts": {
                "dev": "   "
              }
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let result = ProjectCommandSnapshotResolver.analyzedSnapshot(
            for: .devServer,
            path: projectRoot.path
        )

        guard case .failure(.missingDevelopmentScript(.devServer)) = result else {
            Issue.record("expected a blank development script to be rejected")
            return
        }
    }

    private func makeProject(packageJSON: String, lockfile: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try packageJSON.write(
            to: root.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        if let lockfile {
            try "".write(
                to: root.appendingPathComponent(lockfile),
                atomically: true,
                encoding: .utf8
            )
        }
        return root
    }
}
