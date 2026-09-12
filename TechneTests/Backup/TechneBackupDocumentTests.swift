import Foundation
import Testing
@testable import Techne

struct TechneBackupDocumentTests {
    @Test
    func backupDocumentRoundTripsProjectsAndConfigs() throws {
        let payload = TechneBackupPayload(
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
                    discardChangesCommand: "git reset --hard && git clean -fd",
                    installCommand: "pnpm install",
                    stopCommand: ""
                )
            ]
        )

        let document = TechneBackupDocument(payload: payload)
        let data = try document.serializedData()
        let restored = try TechneBackupDocument(data: data)

        #expect(restored.payload.projects.count == 1)
        #expect(restored.payload.commandConfigs.count == 1)
        #expect(restored.payload.projects[0].installStrategy == .ifMissing)
        #expect(restored.payload.projects[0].commandProfileName == "Vite + pnpm")
    }
}
