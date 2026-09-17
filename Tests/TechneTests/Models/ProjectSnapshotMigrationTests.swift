import Foundation
import Testing
@testable import Techne

struct ProjectSnapshotMigrationTests {
    @Test
    func persistenceRootApplicationSupportMatchesLegacyLocation() {
        let root = PersistenceRoot.applicationSupport()
        let expectedPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "studio.slippindylan.Techne", isDirectory: true)
            .path

        #expect(root.directoryURL.path == expectedPath)
    }

    @Test
    func persistenceServiceSupportsExplicitPersistenceRoot() throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: isolatedPersistenceRoot)
        }

        let persistence = PersistenceService<CommandConfig>(
            filename: "commandconfigs.json",
            root: .custom(isolatedPersistenceRoot)
        )

        #expect(persistence.storageURL.deletingLastPathComponent().path == isolatedPersistenceRoot.path)
    }

    @Test
    @MainActor
    func commandConfigServiceLeavesEmptyPersistenceEmpty() throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: isolatedPersistenceRoot)
        }

        let persistence = PersistenceService<CommandConfig>(
            filename: "commandconfigs.json",
            root: .custom(isolatedPersistenceRoot)
        )

        let service = CommandConfigService(persistenceService: persistence)

        #expect(service.configs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: persistence.storageURL.path) == false)
    }

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
        #expect(project.preparedDependencyFingerprint == nil)
        #expect(project.runtimeKind == .shell)
    }

    @Test
    func nativeWeChatRuntimeRoundTripsWithoutShellStartupState() throws {
        let project = Project(
            name: "native-mini-app",
            path: "/tmp/native-mini-app",
            type: .miniApp,
            startCommand: "should not survive",
            commandProfileName: "自动识别 · 原生微信小程序",
            installStrategy: .never,
            runtimeKind: .weChatNative,
            availableStartupModes: [
                ProjectStartupMode(
                    id: "dev",
                    displayName: "默认",
                    startCommand: "should not survive",
                    source: .autoDetected
                )
            ],
            selectedStartupModeID: "dev"
        )

        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        let migrated = ProjectPersistenceMigration.migrate(projects: [restored], commandConfigs: [])
            .projects[0]

        #expect(migrated.runtimeKind == .weChatNative)
        #expect(migrated.startCommand.isEmpty)
        #expect(migrated.availableStartupModes.isEmpty)
        #expect(migrated.selectedStartupModeID == nil)
        #expect(migrated.installStrategy == .never)
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
    func addProjectUsesResolvedCommandSnapshotWithoutLegacyConfigSelection() throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: isolatedPersistenceRoot)
        }

        let projectPersistence = PersistenceService<Project>(
            filename: "projects.json",
            root: .custom(isolatedPersistenceRoot)
        )
        let configService = CommandConfigService(
            persistenceService: PersistenceService<CommandConfig>(
                filename: "commandconfigs.json",
                root: .custom(isolatedPersistenceRoot)
            )
        )

        let service = ProjectService(
            commandConfigService: configService,
            persistenceService: projectPersistence
        )
        let projectURL = makeNonTemporaryFixtureDirectory(named: "frontend-app")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try """
        {
          "name": "frontend-app",
          "scripts": {
            "dev": "vite",
            "build": "vite build"
          },
          "devDependencies": {
            "vite": "^5.0.0"
          }
        }
        """.write(to: projectURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectURL.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectURL.deletingLastPathComponent())
        }

        let result = service.addProject(path: projectURL.path, type: .devServer)

        guard case .success(let project) = result else {
            Issue.record("expected project creation success")
            return
        }

        #expect(project.commandConfigId == nil)
        #expect(project.startCommand == "pnpm dev")
        #expect(project.buildCommand == "pnpm build")
        #expect(project.cleanCommand.isEmpty)
        #expect(project.installCommand == "pnpm install")
        #expect(project.stopCommand == "由 Techne 自动停止关联进程")
        #expect(project.discardChangesCommand == "git restore . && git clean -fd")
        #expect(project.commandProfileName == "自动识别 · Vite + pnpm")
        #expect(projectPersistence.storageURL.deletingLastPathComponent().path == isolatedPersistenceRoot.path)
    }

    @Test
    func backfillMissingCommandSnapshotOnlyFillsEmptyFields() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
        }
        try """
        {
          "name": "mini-program",
          "scripts": {
            "dev:mp-weixin": "uni -p mp-weixin",
            "build:mp-weixin": "uni build -p mp-weixin"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)

        let project = Project(
            name: "mini-program",
            path: projectRoot.path,
            type: .miniApp,
            startCommand: "custom start",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "custom install",
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: nil,
            commandConfigId: UUID()
        )

        let updated = ProjectCommandSnapshotResolver.backfillingMissingSnapshot(for: project)

        #expect(updated.startCommand == "custom start")
        #expect(updated.buildCommand == "pnpm build:mp-weixin")
        #expect(updated.cleanCommand == "rm -rf dist")
        #expect(updated.installCommand == "custom install")
        #expect(updated.stopCommand == "由 Techne 自动停止关联进程")
        #expect(updated.discardChangesCommand == "git restore . && git clean -fd")
        #expect(updated.commandProfileName == "自动识别 · 微信小程序 + pnpm")
    }

    @Test
    @MainActor
    func loadProjectsRemovesTemporaryProjectsAndRelatedSnapshotConfigs() throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: isolatedPersistenceRoot)
        }

        let tempConfig = CommandConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Snapshot Config 00000000-0000-0000-0000-000000000101",
            projectType: .devServer,
            startCommand: "pnpm dev",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "pnpm install",
            stopCommand: ""
        )
        let keptConfig = CommandConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            name: "User Saved Template",
            projectType: .devServer,
            startCommand: "npm run dev",
            buildCommand: "npm run build",
            cleanCommand: "rm -rf dist",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "npm install",
            stopCommand: ""
        )
        let configPersistence = PersistenceService<CommandConfig>(
            filename: "commandconfigs.json",
            root: .custom(isolatedPersistenceRoot)
        )
        let projectPersistence = PersistenceService<Project>(
            filename: "projects.json",
            root: .custom(isolatedPersistenceRoot)
        )
        _ = configPersistence.save([tempConfig, keptConfig])
        _ = projectPersistence.save([
            Project(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                name: "blog",
                path: "/Users/test/blog",
                type: .devServer,
                startCommand: "pnpm dev",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing
            ),
            Project(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                name: "snapshot-temp",
                path: "/var/folders/aa/bb/T/Techne-snapshot-temp",
                type: .devServer,
                startCommand: "pnpm dev",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing,
                commandConfigId: tempConfig.id
            )
        ])

        let configService = CommandConfigService(persistenceService: configPersistence)
        let service = ProjectService(
            commandConfigService: configService,
            persistenceService: projectPersistence
        )

        #expect(service.projects.map(\.name) == ["blog"])
        #expect(configService.configs.map(\.name) == ["User Saved Template"])
    }

    @Test
    @MainActor
    func loadProjectsBackfillsMissingSnapshotWhenLegacyConfigNoLongerExists() throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: isolatedPersistenceRoot)
        }

        let projectRoot = makeNonTemporaryFixtureDirectory(named: "server-ui")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try """
        {
          "name": "server-ui",
          "scripts": {
            "dev": "next dev",
            "build": "next build"
          },
          "dependencies": {
            "next": "^15.0.0"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("package-lock.json"), atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot.deletingLastPathComponent())
        }

        let projectPersistence = PersistenceService<Project>(
            filename: "projects.json",
            root: .custom(isolatedPersistenceRoot)
        )
        _ = projectPersistence.save([
            Project(
                name: "server-ui",
                path: projectRoot.path,
                type: .devServer,
                startCommand: "npm run dev",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing,
                commandConfigId: UUID()
            )
        ])

        let service = ProjectService(
            commandConfigService: CommandConfigService(
                persistenceService: PersistenceService<CommandConfig>(
                    filename: "commandconfigs.json",
                    root: .custom(isolatedPersistenceRoot)
                )
            ),
            persistenceService: projectPersistence
        )

        let restored = try #require(service.projects.first)
        #expect(restored.startCommand == "npm run dev")
        #expect(restored.buildCommand == "npm run build")
        #expect(restored.cleanCommand == "rm -rf .next")
        #expect(restored.installCommand == "npm install")
        #expect(restored.stopCommand == "由 Techne 自动停止关联进程")
        #expect(restored.discardChangesCommand == "git restore . && git clean -fd")
        #expect(restored.commandProfileName == "自动识别 · Next.js + npm")
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
        #expect(details.sections.map(\.title) == ["当前启动模式", "启动命令", "可选启动模式", "安装依赖命令", "构建命令", "清理命令", "停止命令", "丢弃更改命令", "安装策略"])
        #expect(details.sections.map(\.value) == ["默认", "pnpm dev:mp-weixin", "默认: pnpm dev:mp-weixin", "", "", "rm -rf dist", "pkill -f weixin", "", "总是安装"])
    }

    @Test
    func addProjectDetectsMultipleStartupModesAndDefaultsToDev() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try """
        {
          "name": "portlens-workspace",
          "scripts": {
            "dev": "node ./scripts/workspace-next.mjs dev dev-default",
            "dev:mock": "node ./scripts/workspace-next.mjs dev mock",
            "dev:live": "node ./scripts/workspace-next.mjs dev live",
            "build": "next build"
          },
          "dependencies": {
            "next": "^15.0.0"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)

        let project = ProjectCommandSnapshotResolver.makeProject(
            name: "portlens-workspace",
            path: projectRoot.path,
            type: .devServer
        )

        #expect(project.availableStartupModes.map(\.id) == ["dev", "dev:mock", "dev:live"])
        #expect(project.selectedStartupModeID == "dev")
        #expect(project.startCommand == "pnpm dev")
        #expect(project.selectedStartupMode?.displayName == "默认")
    }

    @Test
    func legacyProjectWithoutStartupModesBackfillsSelectedModeFromStartCommand() {
        let legacyProject = Project(
            name: "legacy-app",
            path: "/tmp/legacy-app",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev:mock",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf .next",
            installCommand: "pnpm install",
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Next.js + pnpm"
        )

        let updated = ProjectCommandSnapshotResolver.backfillingMissingSnapshot(for: legacyProject)

        #expect(updated.availableStartupModes.count == 1)
        #expect(updated.availableStartupModes[0].startCommand == "pnpm dev:mock")
        #expect(updated.selectedStartupModeID == updated.availableStartupModes[0].id)
        #expect(updated.startCommand == "pnpm dev:mock")
    }

    @Test
    func selectingStartupModeUpdatesCompatibilityStartCommand() {
        var project = Project(
            name: "frontend-app",
            path: "/tmp/frontend-app",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist",
            installCommand: "pnpm install",
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Vite + pnpm",
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "pnpm dev", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "pnpm dev:mock", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )

        project.selectStartupMode(id: "dev:mock")

        #expect(project.selectedStartupModeID == "dev:mock")
        #expect(project.startCommand == "pnpm dev:mock")
        #expect(project.selectedStartupMode?.displayName == "Mock")
    }

    @Test
    func startupModeDisplayNamesPreferMockAndLiveLabels() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try """
        {
          "name": "workspace",
          "scripts": {
            "dev": "vite",
            "dev:mock": "vite --mode mock",
            "dev:live": "vite --mode live"
          },
          "devDependencies": {
            "vite": "^5.0.0"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)

        let project = ProjectCommandSnapshotResolver.makeProject(
            name: "workspace",
            path: projectRoot.path,
            type: .devServer
        )

        #expect(project.availableStartupModes.map(\.displayName) == ["默认", "Mock", "Live"])
    }

    @Test
    func commandConfigProjectKeepsCustomStartCommandAsOnlyStartupMode() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try """
        {
          "name": "custom-start-app",
          "scripts": {
            "dev": "vite",
            "dev:mock": "vite --mode mock",
            "build": "vite build"
          },
          "devDependencies": {
            "vite": "^5.0.0"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("package-lock.json"), atomically: true, encoding: .utf8)

        let commandConfig = CommandConfig(
            name: "Custom npm profile",
            projectType: .devServer,
            startCommand: "npm run dev:custom",
            buildCommand: "npm run build:custom",
            cleanCommand: "rm -rf custom-dist",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "npm ci",
            stopCommand: "pkill -f custom-vite"
        )

        let project = ProjectCommandSnapshotResolver.makeProject(
            name: "custom-start-app",
            path: projectRoot.path,
            type: .devServer,
            commandConfigId: commandConfig.id,
            legacyConfig: commandConfig
        )

        #expect(project.startCommand == "npm run dev:custom")
        #expect(project.availableStartupModes == [
            ProjectStartupMode(
                id: "default",
                displayName: "默认",
                startCommand: "npm run dev:custom",
                source: .commandConfig
            )
        ])
        #expect(project.selectedStartupModeID == "default")
        #expect(project.selectedStartupMode?.startCommand == "npm run dev:custom")
    }

    @Test
    func migrationRepairsBuggyPersistedCommandConfigStartupSelection() {
        let commandConfig = CommandConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000777")!,
            name: "Custom npm profile",
            projectType: .devServer,
            startCommand: "npm run dev:custom",
            buildCommand: "npm run build:custom",
            cleanCommand: "rm -rf custom-dist",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "npm ci",
            stopCommand: "pkill -f custom-vite"
        )

        let buggyPersistedProject = Project(
            name: "custom-start-app",
            path: "/tmp/custom-start-app",
            type: .devServer,
            currentBranch: "main",
            startCommand: "npm run dev:custom",
            buildCommand: "npm run build:custom",
            cleanCommand: "rm -rf custom-dist",
            installCommand: "npm ci",
            stopCommand: "pkill -f custom-vite",
            discardChangesCommand: "git restore . && git clean -fd",
            commandProfileName: "Custom npm profile",
            commandConfigId: commandConfig.id,
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "npm run dev", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "npm run dev:mock", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )

        let repaired = ProjectCommandSnapshotResolver.backfillingMissingSnapshot(
            for: buggyPersistedProject,
            legacyConfig: commandConfig
        )

        #expect(repaired.startCommand == "npm run dev:custom")
        #expect(repaired.availableStartupModes == [
            ProjectStartupMode(
                id: "default",
                displayName: "默认",
                startCommand: "npm run dev:custom",
                source: .commandConfig
            )
        ])
        #expect(repaired.selectedStartupModeID == "default")
        #expect(repaired.selectedStartupMode?.startCommand == "npm run dev:custom")
    }

    @Test
    func decodingBuggyPersistedStartupModesPreservesPersistedCustomStartCommand() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000778",
          "name": "custom-start-app",
          "path": "/tmp/custom-start-app",
          "type": "开发服务与实例",
          "currentBranch": "main",
          "startCommand": "pnpm dev:mock",
          "buildCommand": "pnpm build",
          "cleanCommand": "rm -rf dist",
          "installCommand": "pnpm install",
          "stopCommand": "由 Techne 自动停止关联进程",
          "discardChangesCommand": "git restore . && git clean -fd",
          "commandProfileName": "自动识别 · Vite + pnpm",
          "availableStartupModes": [
            {
              "id": "dev",
              "displayName": "默认",
              "startCommand": "pnpm dev",
              "source": "autoDetected"
            },
            {
              "id": "dev:live",
              "displayName": "Live",
              "startCommand": "pnpm dev:live",
              "source": "autoDetected"
            }
          ],
          "selectedStartupModeID": "dev",
          "addedDate": 0
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(Project.self, from: json)
        let expectedModes = [
            ProjectStartupMode(
                id: "default",
                displayName: "默认",
                startCommand: "pnpm dev:mock",
                source: .importedLegacy
            )
        ]

        if project.startCommand != "pnpm dev:mock" {
            Issue.record("decoded startCommand was \(project.startCommand)")
        }
        if project.availableStartupModes != expectedModes {
            Issue.record("decoded startupModes were \(project.availableStartupModes)")
        }
        if project.selectedStartupModeID != "default" {
            Issue.record("decoded selectedStartupModeID was \(project.selectedStartupModeID ?? "nil")")
        }
        if project.selectedStartupMode?.startCommand != "pnpm dev:mock" {
            Issue.record("decoded selected mode command was \(project.selectedStartupMode?.startCommand ?? "nil")")
        }

        #expect(project.startCommand == "pnpm dev:mock")
        #expect(project.availableStartupModes == expectedModes)
        #expect(project.selectedStartupModeID == "default")
        #expect(project.selectedStartupMode?.startCommand == "pnpm dev:mock")
    }

    private func makeNonTemporaryFixtureDirectory(named name: String) -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".techne-test-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return root.appendingPathComponent(name, isDirectory: true)
    }
}
