import AppKit
import Foundation

@MainActor
final class BackupService {
    static let defaultFilename = "techne-backup"

    static func mergeProjects(existing: [Project], incoming: [Project]) -> [Project] {
        var seen = Set(existing.map { normalizePath($0.path) })
        var merged = existing

        for project in incoming {
            let normalizedPath = normalizePath(project.path)
            guard !seen.contains(normalizedPath) else { continue }
            merged.append(project)
            seen.insert(normalizedPath)
        }

        return merged
    }

    static func mergeConfigs(existing: [CommandConfig], incoming: [CommandConfig]) -> [CommandConfig] {
        var seen = Set(existing.map(\.name))
        var merged = existing

        for config in incoming where !seen.contains(config.name) {
            merged.append(config)
            seen.insert(config.name)
        }

        return merged
    }

    static func makeDocument(
        projects: [Project],
        commandConfigs: [CommandConfig],
        appVersion: String? = nil
    ) -> TechneBackupDocument {
        TechneBackupDocument(
            payload: makePayload(
                projects: projects,
                commandConfigs: commandConfigs,
                appVersion: resolvedAppVersion(appVersion)
            )
        )
    }

    static func makePayload(
        projects: [Project],
        commandConfigs: [CommandConfig],
        appVersion: String
    ) -> TechneBackupPayload {
        TechneBackupPayload(
            schemaVersion: 1,
            exportedAt: Date(),
            appVersion: appVersion,
            projects: projects,
            commandConfigs: commandConfigs
        )
    }

    static func payload(from data: Data) throws -> TechneBackupPayload {
        try TechneBackupDocument(data: data).payload
    }

    static func mergeImport(
        from url: URL,
        projectService: ProjectService,
        commandConfigService: CommandConfigService
    ) throws {
        let payload = try withSecurityScopedAccess(to: url) {
            let data = try Data(contentsOf: url)
            return try self.payload(from: data)
        }

        commandConfigService.mergeImportedConfigs(payload.commandConfigs)
        projectService.mergeImportedProjects(payload.projects)
    }

    static func revealAppSupportDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([applicationSupportDirectoryURL()])
    }

    private static func applicationSupportDirectoryURL() -> URL {
        PersistenceService<Project>(filename: "projects.json").storageURL.deletingLastPathComponent()
    }

    private static func resolvedAppVersion(_ explicitVersion: String?) -> String {
        let trimmedVersion = explicitVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedVersion, !trimmedVersion.isEmpty {
            return trimmedVersion
        }

        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"
    }

    private static func normalizePath(_ path: String) -> String {
        ProjectPath.canonical(path)
    }

    private static func withSecurityScopedAccess<T>(to url: URL, _ work: () throws -> T) throws -> T {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try work()
    }
}
