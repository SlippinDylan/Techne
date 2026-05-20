import Foundation
import Testing
@testable import DevNexus

struct ProjectSnapshotMigrationTests {
    @Test
    func legacyProjectDecodesWithDefaultCommandSnapshot() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-app",
          "path": "/tmp/legacy-app",
          "type": "开发服务与实例",
          "currentBranch": "main",
          "startCommand": "pnpm dev",
          "addedDate": 0
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(Project.self, from: json)

        #expect(project.startCommand == "pnpm dev")
        #expect(project.buildCommand == "")
        #expect(project.installCommand == "")
        #expect(project.commandProfileName == nil)
        #expect(project.installStrategy == .ifMissing)
    }

    @Test
    func projectInitializedFromCommandConfigCapturesFullSnapshot() {
        let config = CommandConfig(
            name: "Vite + pnpm",
            projectType: .devServer,
            startCommand: "pnpm dev",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist node_modules/.cache",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "pnpm install",
            stopCommand: "pkill -f vite"
        )

        let project = Project(
            name: "frontend-app",
            path: "/tmp/frontend-app",
            type: .devServer,
            commandConfigId: config.id,
            commandConfig: config
        )

        #expect(project.commandConfigId == config.id)
        #expect(project.startCommand == "pnpm dev")
        #expect(project.buildCommand == "pnpm build")
        #expect(project.cleanCommand == "rm -rf dist node_modules/.cache")
        #expect(project.installCommand == "pnpm install")
        #expect(project.stopCommand == "pkill -f vite")
        #expect(project.discardChangesCommand == "git restore . && git clean -fd")
        #expect(project.commandProfileName == "Vite + pnpm")
    }

    @Test
    func backfillMissingCommandSnapshotOnlyFillsEmptyFields() {
        let config = CommandConfig(
            name: "Mini App + pnpm",
            projectType: .miniApp,
            startCommand: "pnpm dev:mp-weixin",
            buildCommand: "pnpm build:mp-weixin",
            cleanCommand: "rm -rf dist",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "pnpm install",
            stopCommand: "pkill -f weixin"
        )

        let project = Project(
            name: "mini-program",
            path: "/tmp/mini-program",
            type: .miniApp,
            startCommand: "custom start",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "custom install",
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: nil,
            commandConfigId: config.id
        )

        let updated = project.backfillingMissingCommandSnapshot(from: config)

        #expect(updated.startCommand == "custom start")
        #expect(updated.buildCommand == "pnpm build:mp-weixin")
        #expect(updated.cleanCommand == "rm -rf dist")
        #expect(updated.installCommand == "custom install")
        #expect(updated.stopCommand == "pkill -f weixin")
        #expect(updated.discardChangesCommand == "git restore . && git clean -fd")
        #expect(updated.commandProfileName == "Mini App + pnpm")
    }
}
