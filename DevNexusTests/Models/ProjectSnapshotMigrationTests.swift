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
    @MainActor
    func addProjectCopiesSelectedConfigIntoProjectSnapshot() throws {
        let configService = CommandConfigService()
        let config = CommandConfig(
            name: "Snapshot Config \(UUID().uuidString)",
            projectType: .devServer,
            startCommand: "pnpm dev --host",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist .vite",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "pnpm install --frozen-lockfile",
            stopCommand: "pkill -f vite"
        )
        _ = configService.addConfig(config)

        let service = ProjectService(commandConfigService: configService)
        let projectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: projectURL)
        }

        let result = service.addProject(path: projectURL.path, type: .devServer, configId: config.id)

        guard case .success(let project) = result else {
            Issue.record("expected project creation success")
            return
        }

        #expect(project.commandConfigId == config.id)
        #expect(project.startCommand == "pnpm dev --host")
        #expect(project.buildCommand == "pnpm build")
        #expect(project.cleanCommand == "rm -rf dist .vite")
        #expect(project.installCommand == "pnpm install --frozen-lockfile")
        #expect(project.stopCommand == "pkill -f vite")
        #expect(project.discardChangesCommand == "git restore . && git clean -fd")
        #expect(project.commandProfileName == config.name)
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

    @Test
    func commandDetailsPresentationUsesProjectSnapshotWithoutTemplateLookup() {
        let project = Project(
            name: "custom-app",
            path: "/tmp/custom-app",
            type: .miniApp,
            startCommand: "pnpm dev:mp-weixin",
            buildCommand: "",
            cleanCommand: "rm -rf dist",
            installCommand: "",
            stopCommand: "pkill -f weixin",
            discardChangesCommand: "",
            commandProfileName: nil,
            installStrategy: .always,
            commandConfigId: UUID()
        )

        let details = ProjectCommandDetails(project: project)

        #expect(details.profileDisplayName == "自定义命令")
        #expect(details.sections.map(\.title) == ["启动命令", "安装依赖命令", "构建命令", "清理命令", "停止命令", "丢弃更改命令", "安装策略"])
        #expect(details.sections.map(\.value) == ["pnpm dev:mp-weixin", "", "", "rm -rf dist", "pkill -f weixin", "", "总是安装"])
    }
}
