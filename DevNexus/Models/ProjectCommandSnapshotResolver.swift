import Foundation

struct ProjectCommandSnapshot: Equatable, Sendable {
    static let managedStopCommand = "由 DevNexus 自动停止关联进程"
    static let defaultDiscardChangesCommand = "git restore . && git clean -fd"

    let startCommand: String
    let startupModes: [ProjectStartupMode]
    let selectedStartupModeID: String?
    let buildCommand: String
    let cleanCommand: String
    let installCommand: String
    let stopCommand: String
    let discardChangesCommand: String
    let commandProfileName: String
    let installStrategy: InstallStrategy
}

struct ProjectCommandSnapshotResolver {
    static func makeProject(
        name: String,
        path: String,
        type: ProjectType,
        commandConfigId: UUID? = nil,
        legacyConfig: CommandConfig? = nil,
        fileManager: FileManager = .default
    ) -> Project {
        let snapshot = resolvedSnapshot(
            for: type,
            path: path,
            legacyConfig: legacyConfig,
            fileManager: fileManager
        )

        return Project(
            name: name,
            path: path,
            type: type,
            startCommand: snapshot.startCommand,
            buildCommand: snapshot.buildCommand,
            cleanCommand: snapshot.cleanCommand,
            installCommand: snapshot.installCommand,
            stopCommand: snapshot.stopCommand,
            discardChangesCommand: snapshot.discardChangesCommand,
            commandProfileName: snapshot.commandProfileName,
            installStrategy: snapshot.installStrategy,
            commandConfigId: commandConfigId,
            availableStartupModes: snapshot.startupModes,
            selectedStartupModeID: snapshot.selectedStartupModeID
        )
    }

    static func resolvedSnapshot(
        for type: ProjectType,
        path: String,
        legacyConfig: CommandConfig? = nil,
        fileManager: FileManager = .default
    ) -> ProjectCommandSnapshot {
        let builtin = builtinSnapshot(for: type, path: path, fileManager: fileManager)
        guard let legacyConfig else {
            return builtin
        }

        let legacy = snapshot(from: legacyConfig)
        return ProjectCommandSnapshot(
            startCommand: preferredCommand(primary: legacy.startCommand, fallback: builtin.startCommand),
            startupModes: builtin.startupModes,
            selectedStartupModeID: builtin.selectedStartupModeID,
            buildCommand: preferredCommand(primary: legacy.buildCommand, fallback: builtin.buildCommand),
            cleanCommand: preferredCommand(primary: legacy.cleanCommand, fallback: builtin.cleanCommand),
            installCommand: preferredCommand(primary: legacy.installCommand, fallback: builtin.installCommand),
            stopCommand: preferredCommand(primary: legacy.stopCommand, fallback: builtin.stopCommand),
            discardChangesCommand: preferredCommand(primary: legacy.discardChangesCommand, fallback: builtin.discardChangesCommand),
            commandProfileName: preferredCommand(primary: legacy.commandProfileName, fallback: builtin.commandProfileName),
            installStrategy: builtin.installStrategy
        )
    }

    static func backfillingMissingSnapshot(
        for project: Project,
        legacyConfig: CommandConfig? = nil,
        fileManager: FileManager = .default
    ) -> Project {
        let snapshot = resolvedSnapshot(
            for: project.type,
            path: project.path,
            legacyConfig: legacyConfig,
            fileManager: fileManager
        )
        return project.backfillingMissingCommandSnapshot(from: snapshot)
    }

    private static func snapshot(from config: CommandConfig) -> ProjectCommandSnapshot {
        let startupMode = ProjectStartupMode(
            id: "default",
            displayName: "默认",
            startCommand: config.startCommand,
            source: .commandConfig
        )
        return ProjectCommandSnapshot(
            startCommand: config.startCommand,
            startupModes: [startupMode],
            selectedStartupModeID: startupMode.id,
            buildCommand: config.buildCommand,
            cleanCommand: config.cleanCommand,
            installCommand: config.installCommand,
            stopCommand: config.stopCommand,
            discardChangesCommand: config.discardChangesCommand,
            commandProfileName: config.name,
            installStrategy: .ifMissing
        )
    }

    private static func builtinSnapshot(
        for type: ProjectType,
        path: String,
        fileManager: FileManager
    ) -> ProjectCommandSnapshot {
        let manifest = loadManifest(at: path)
        let packageManager = detectPackageManager(at: path, manifest: manifest, fileManager: fileManager)

        switch type {
        case .devServer:
            if isNextProject(manifest) {
                return nextSnapshot(packageManager: packageManager, manifest: manifest)
            }
            if isViteProject(manifest) {
                return viteSnapshot(packageManager: packageManager, manifest: manifest)
            }
            return genericDevServerSnapshot(packageManager: packageManager, manifest: manifest)
        case .miniApp:
            return miniAppSnapshot(packageManager: packageManager, manifest: manifest)
        }
    }

    private static func viteSnapshot(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> ProjectCommandSnapshot {
        let startupModes = resolvedStartupModes(packageManager: packageManager, manifest: manifest)
        let selectedMode = selectedStartupMode(from: startupModes)
        return ProjectCommandSnapshot(
            startCommand: selectedMode.startCommand,
            startupModes: startupModes,
            selectedStartupModeID: selectedMode.id,
            buildCommand: commandForFirstScript(["build"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("build"),
            cleanCommand: commandForScript("clean", packageManager: packageManager, manifest: manifest) ?? "rm -rf dist node_modules/.cache .vite",
            installCommand: packageManager.installCommand,
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Vite + \(packageManager.rawValue)",
            installStrategy: .ifMissing
        )
    }

    private static func nextSnapshot(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> ProjectCommandSnapshot {
        let startupModes = resolvedStartupModes(packageManager: packageManager, manifest: manifest)
        let selectedMode = selectedStartupMode(from: startupModes)
        return ProjectCommandSnapshot(
            startCommand: selectedMode.startCommand,
            startupModes: startupModes,
            selectedStartupModeID: selectedMode.id,
            buildCommand: commandForFirstScript(["build"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("build"),
            cleanCommand: commandForScript("clean", packageManager: packageManager, manifest: manifest) ?? "rm -rf .next",
            installCommand: packageManager.installCommand,
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Next.js + \(packageManager.rawValue)",
            installStrategy: .ifMissing
        )
    }

    private static func genericDevServerSnapshot(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> ProjectCommandSnapshot {
        let startupModes = resolvedStartupModes(packageManager: packageManager, manifest: manifest)
        let selectedMode = selectedStartupMode(from: startupModes)
        return ProjectCommandSnapshot(
            startCommand: selectedMode.startCommand,
            startupModes: startupModes,
            selectedStartupModeID: selectedMode.id,
            buildCommand: commandForFirstScript(["build"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("build"),
            cleanCommand: commandForScript("clean", packageManager: packageManager, manifest: manifest) ?? "rm -rf dist .cache",
            installCommand: packageManager.installCommand,
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · 开发服务 + \(packageManager.rawValue)",
            installStrategy: .ifMissing
        )
    }

    private static func miniAppSnapshot(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> ProjectCommandSnapshot {
        let startCommand = commandForFirstScript(["dev:mp-weixin", "dev:mp", "dev", "start"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("dev:mp-weixin")
        let startupMode = ProjectStartupMode(
            id: "default",
            displayName: "默认",
            startCommand: startCommand,
            source: .autoDetected
        )
        return ProjectCommandSnapshot(
            startCommand: startCommand,
            startupModes: [startupMode],
            selectedStartupModeID: startupMode.id,
            buildCommand: commandForFirstScript(["build:mp-weixin", "build:mp", "build"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("build:mp-weixin"),
            cleanCommand: commandForScript("clean", packageManager: packageManager, manifest: manifest) ?? "rm -rf dist",
            installCommand: packageManager.installCommand,
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · 微信小程序 + \(packageManager.rawValue)",
            installStrategy: .ifMissing
        )
    }

    private static func commandForFirstScript(
        _ names: [String],
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> String? {
        for name in names {
            if let command = commandForScript(name, packageManager: packageManager, manifest: manifest) {
                return command
            }
        }
        return nil
    }

    private static func commandForScript(
        _ name: String,
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> String? {
        guard manifest?.scripts?[name] != nil else {
            return nil
        }
        return packageManager.runCommand(name)
    }

    private static func detectedStartupModes(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> [ProjectStartupMode] {
        let candidates: [(String, String)] = [
            ("dev", "默认"),
            ("dev:mock", "Mock"),
            ("dev:live", "Live"),
            ("mock", "Mock"),
            ("start", "Start")
        ]

        return candidates.compactMap { scriptName, displayName in
            guard manifest?.scripts?[scriptName] != nil else {
                return nil
            }
            return ProjectStartupMode(
                id: scriptName,
                displayName: displayName,
                startCommand: packageManager.runCommand(scriptName),
                source: .autoDetected
            )
        }
    }

    private static func resolvedStartupModes(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> [ProjectStartupMode] {
        let detectedModes = detectedStartupModes(packageManager: packageManager, manifest: manifest)
        if detectedModes.isEmpty {
            return [
                ProjectStartupMode(
                    id: "default",
                    displayName: "默认",
                    startCommand: commandForFirstScript(["dev", "start"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("dev"),
                    source: .autoDetected
                )
            ]
        }
        return detectedModes
    }

    private static func selectedStartupMode(from startupModes: [ProjectStartupMode]) -> ProjectStartupMode {
        startupModes.first(where: { $0.id == "dev" }) ?? startupModes[0]
    }

    private static func preferredCommand(primary: String, fallback: String) -> String {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrimary.isEmpty ? fallback : trimmedPrimary
    }

    private static func detectPackageManager(
        at path: String,
        manifest: PackageManifest?,
        fileManager: FileManager
    ) -> ProjectPackageManager {
        if let rawPackageManager = manifest?.packageManager?.split(separator: "@").first,
           let packageManager = ProjectPackageManager(rawValue: String(rawPackageManager)) {
            return packageManager
        }

        let rootURL = URL(fileURLWithPath: path)
        let knownFiles: [(String, ProjectPackageManager)] = [
            ("pnpm-lock.yaml", .pnpm),
            ("package-lock.json", .npm),
            ("yarn.lock", .yarn),
            ("bun.lock", .bun),
            ("bun.lockb", .bun)
        ]

        for (filename, packageManager) in knownFiles {
            if fileManager.fileExists(atPath: rootURL.appendingPathComponent(filename).path) {
                return packageManager
            }
        }

        return .pnpm
    }

    private static func loadManifest(at path: String) -> PackageManifest? {
        let packageJSONURL = URL(fileURLWithPath: path).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSONURL) else {
            return nil
        }
        return try? JSONDecoder().decode(PackageManifest.self, from: data)
    }

    private static func isNextProject(_ manifest: PackageManifest?) -> Bool {
        manifest?.hasDependency(named: "next") == true ||
        manifest?.scriptValues.contains(where: { $0.localizedCaseInsensitiveContains("next ") }) == true
    }

    private static func isViteProject(_ manifest: PackageManifest?) -> Bool {
        manifest?.hasDependency(named: "vite") == true ||
        manifest?.scriptValues.contains(where: { $0.localizedCaseInsensitiveContains("vite") }) == true
    }
}

private enum ProjectPackageManager: String, Sendable {
    case pnpm
    case npm
    case yarn
    case bun

    var installCommand: String {
        switch self {
        case .pnpm:
            return "pnpm install"
        case .npm:
            return "npm install"
        case .yarn:
            return "yarn install"
        case .bun:
            return "bun install"
        }
    }

    func runCommand(_ scriptName: String) -> String {
        switch self {
        case .pnpm:
            return "pnpm \(scriptName)"
        case .npm:
            return "npm run \(scriptName)"
        case .yarn:
            return "yarn \(scriptName)"
        case .bun:
            return "bun run \(scriptName)"
        }
    }
}

private struct PackageManifest: Decodable, Sendable {
    let packageManager: String?
    let scripts: [String: String]?
    let dependencies: [String: String]?
    let devDependencies: [String: String]?

    var scriptValues: [String] {
        Array((scripts ?? [:]).values)
    }

    func hasDependency(named packageName: String) -> Bool {
        dependencies?[packageName] != nil || devDependencies?[packageName] != nil
    }
}

struct ProjectPersistenceMigrationResult: Sendable {
    let projects: [Project]
    let commandConfigs: [CommandConfig]
    let didChange: Bool
}

struct ProjectPersistenceMigration {
    static func migrate(
        projects: [Project],
        commandConfigs: [CommandConfig],
        fileManager: FileManager = .default
    ) -> ProjectPersistenceMigrationResult {
        let persistedProjects = projects.filter { !isTemporaryProjectPath($0.path) }
        let retainedConfigIDs = Set(persistedProjects.compactMap(\.commandConfigId))
        let retainedConfigs = commandConfigs.filter { !isGarbageSnapshotConfig($0, retainedConfigIDs: retainedConfigIDs) }
        let configsByID = Dictionary(uniqueKeysWithValues: retainedConfigs.map { ($0.id, $0) })
        let normalizedProjects = persistedProjects.map { project in
            ProjectCommandSnapshotResolver.backfillingMissingSnapshot(
                for: project,
                legacyConfig: project.commandConfigId.flatMap { configsByID[$0] },
                fileManager: fileManager
            )
        }

        let didChange = projectsChanged(from: projects, to: normalizedProjects) ||
            configsChanged(from: commandConfigs, to: retainedConfigs)
        return ProjectPersistenceMigrationResult(
            projects: normalizedProjects,
            commandConfigs: retainedConfigs,
            didChange: didChange
        )
    }

    static func isTemporaryProjectPath(_ path: String, fileManager: FileManager = .default) -> Bool {
        let normalizedPath = normalize(path)
        let temporaryRoot = fileManager.temporaryDirectory.standardizedFileURL.path

        return normalizedPath == temporaryRoot ||
            normalizedPath.hasPrefix(temporaryRoot + "/") ||
            normalizedPath.contains("/var/folders/") && normalizedPath.contains("/T/")
    }

    private static func isGarbageSnapshotConfig(_ config: CommandConfig, retainedConfigIDs: Set<UUID>) -> Bool {
        guard config.name.hasPrefix("Snapshot Config ") else {
            return false
        }

        return retainedConfigIDs.contains(config.id) == false
    }

    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private static func projectsChanged(from original: [Project], to normalized: [Project]) -> Bool {
        guard original.count == normalized.count else {
            return true
        }

        return zip(original, normalized).contains { lhs, rhs in
            lhs.id != rhs.id ||
            lhs.path != rhs.path ||
            lhs.startCommand != rhs.startCommand ||
            lhs.buildCommand != rhs.buildCommand ||
            lhs.cleanCommand != rhs.cleanCommand ||
            lhs.installCommand != rhs.installCommand ||
            lhs.stopCommand != rhs.stopCommand ||
            lhs.discardChangesCommand != rhs.discardChangesCommand ||
            lhs.commandProfileName != rhs.commandProfileName ||
            lhs.commandConfigId != rhs.commandConfigId
        }
    }

    private static func configsChanged(from original: [CommandConfig], to normalized: [CommandConfig]) -> Bool {
        guard original.count == normalized.count else {
            return true
        }

        return zip(original, normalized).contains { lhs, rhs in
            lhs.id != rhs.id ||
            lhs.name != rhs.name ||
            lhs.projectType != rhs.projectType ||
            lhs.startCommand != rhs.startCommand ||
            lhs.buildCommand != rhs.buildCommand ||
            lhs.cleanCommand != rhs.cleanCommand ||
            lhs.installCommand != rhs.installCommand ||
            lhs.stopCommand != rhs.stopCommand ||
            lhs.discardChangesCommand != rhs.discardChangesCommand
        }
    }
}
