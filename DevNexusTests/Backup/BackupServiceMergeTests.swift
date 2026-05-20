import Foundation
import Testing
@testable import DevNexus

struct BackupServiceMergeTests {
    @Test
    func mergeImportSkipsDuplicateProjectPaths() {
        let existing = [
            Project(
                name: "frontend-app",
                path: "/tmp/frontend-app",
                type: .devServer,
                currentBranch: "main",
                startCommand: "pnpm dev",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "pnpm install",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing
            )
        ]

        let incoming = existing + [
            Project(
                name: "mini-program",
                path: "/tmp/mini-program",
                type: .miniApp,
                currentBranch: "main",
                startCommand: "pnpm dev:mp-weixin",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "pnpm install",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing
            )
        ]

        let merged = BackupService.mergeProjects(existing: existing, incoming: incoming)
        #expect(merged.count == 2)
    }

    @Test
    func mergeImportSkipsDuplicateConfigNames() {
        let existing = [
            CommandConfig(
                name: "Vite + pnpm",
                projectType: .devServer,
                startCommand: "pnpm dev",
                buildCommand: "pnpm build",
                cleanCommand: "rm -rf dist",
                discardChangesCommand: "git restore . && git clean -fd",
                installCommand: "pnpm install",
                stopCommand: ""
            )
        ]

        let incoming = existing + [
            CommandConfig(
                name: "Mini App + pnpm",
                projectType: .miniApp,
                startCommand: "pnpm dev:mp-weixin",
                buildCommand: "pnpm build:mp-weixin",
                cleanCommand: "rm -rf dist",
                discardChangesCommand: "git restore . && git clean -fd",
                installCommand: "pnpm install",
                stopCommand: ""
            )
        ]

        let merged = BackupService.mergeConfigs(existing: existing, incoming: incoming)
        #expect(merged.count == 2)
    }

    @Test
    func backupPayloadDecodesFromSerializedDocumentData() throws {
        let payload = DevNexusBackupPayload(
            schemaVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_715_768_000),
            appVersion: "1.0.0",
            projects: [
                Project(
                    name: "frontend-app",
                    path: "/tmp/frontend-app",
                    type: .devServer,
                    currentBranch: "main",
                    startCommand: "pnpm dev",
                    buildCommand: "pnpm build",
                    cleanCommand: "rm -rf dist",
                    installCommand: "pnpm install",
                    stopCommand: "",
                    discardChangesCommand: "git restore . && git clean -fd",
                    commandProfileName: "Vite + pnpm",
                    installStrategy: .ifMissing
                )
            ],
            commandConfigs: [
                CommandConfig(
                    name: "Vite + pnpm",
                    projectType: .devServer,
                    startCommand: "pnpm dev",
                    buildCommand: "pnpm build",
                    cleanCommand: "rm -rf dist",
                    discardChangesCommand: "git restore . && git clean -fd",
                    installCommand: "pnpm install",
                    stopCommand: ""
                )
            ]
        )

        let data = try DevNexusBackupDocument(payload: payload).serializedData()
        let decoded = try BackupService.payload(from: data)

        #expect(decoded.projects.count == 1)
        #expect(decoded.commandConfigs.count == 1)
        #expect(decoded.appVersion == "1.0.0")
    }
}
