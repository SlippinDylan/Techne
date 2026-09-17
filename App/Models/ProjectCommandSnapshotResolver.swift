import Foundation

struct ProjectCommandSnapshot: Equatable, Sendable {
    static let managedStopCommand = "由 Techne 自动停止关联进程"
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
    let runtimeKind: ProjectRuntimeKind

    init(
        startCommand: String,
        startupModes: [ProjectStartupMode],
        selectedStartupModeID: String?,
        buildCommand: String,
        cleanCommand: String,
        installCommand: String,
        stopCommand: String,
        discardChangesCommand: String,
        commandProfileName: String,
        installStrategy: InstallStrategy,
        runtimeKind: ProjectRuntimeKind = .shell
    ) {
        self.startCommand = startCommand
        self.startupModes = startupModes
        self.selectedStartupModeID = selectedStartupModeID
        self.buildCommand = buildCommand
        self.cleanCommand = cleanCommand
        self.installCommand = installCommand
        self.stopCommand = stopCommand
        self.discardChangesCommand = discardChangesCommand
        self.commandProfileName = commandProfileName
        self.installStrategy = installStrategy
        self.runtimeKind = runtimeKind
    }
}

enum ProjectAnalysisError: LocalizedError, Equatable, Sendable {
    case missingPackageManifest
    case invalidPackageManifest
    case missingDevelopmentScript(ProjectType)

    var errorDescription: String? {
        switch self {
        case .missingPackageManifest:
            return "未找到 package.json，无法确认项目的安装和启动方式"
        case .invalidPackageManifest:
            return "package.json 格式无效，无法读取项目命令"
        case .missingDevelopmentScript(.devServer):
            return "package.json 未声明可运行的 dev、dev:*、start 或 serve 脚本"
        case .missingDevelopmentScript(.miniApp):
            return "package.json 未声明可运行的微信小程序开发脚本"
        }
    }
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

        return makeProject(
            name: name,
            path: path,
            type: type,
            commandConfigId: commandConfigId,
            snapshot: snapshot
        )
    }

    static func makeProject(
        name: String,
        path: String,
        type: ProjectType,
        commandConfigId: UUID? = nil,
        snapshot: ProjectCommandSnapshot
    ) -> Project {
        Project(
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
            runtimeKind: snapshot.runtimeKind,
            commandConfigId: commandConfigId,
            availableStartupModes: snapshot.startupModes,
            selectedStartupModeID: snapshot.selectedStartupModeID
        )
    }

    static func analyzedSnapshot(
        for type: ProjectType,
        path: String,
        fileManager: FileManager = .default
    ) -> Result<ProjectCommandSnapshot, ProjectAnalysisError> {
        let manifestURL = URL(fileURLWithPath: path).appendingPathComponent("package.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            if type == .miniApp,
               WeChatProjectLocator.hasRootProjectConfiguration(at: path, fileManager: fileManager) {
                return .success(nativeMiniAppSnapshot())
            }
            return .failure(.missingPackageManifest)
        }

        let manifest: PackageManifest
        do {
            manifest = try JSONDecoder().decode(PackageManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            return .failure(.invalidPackageManifest)
        }

        let dependencyState = ProjectDependencyResolver.state(at: path, fileManager: fileManager)
        let packageManager = detectPackageManager(
            at: dependencyState.workspaceRootPath,
            manifest: manifest,
            fileManager: fileManager,
            defaultPackageManager: .npm
        )
        let startupModes: [ProjectStartupMode]
        let buildScriptNames: [String]
        let profileName: String

        switch type {
        case .devServer:
            startupModes = detectedStartupModes(packageManager: packageManager, manifest: manifest)
            buildScriptNames = ["build"]
            if isNextProject(manifest) {
                profileName = "Next.js"
            } else if isViteProject(manifest) {
                profileName = "Vite"
            } else {
                profileName = "开发服务"
            }
        case .miniApp:
            startupModes = detectedMiniAppStartupModes(packageManager: packageManager, manifest: manifest)
            buildScriptNames = ["build:weapp", "build:mp-weixin", "build:mp", "build"]
            profileName = miniAppFrameworkName(manifest)
        }

        guard startupModes.isEmpty == false else {
            if type == .miniApp,
               WeChatProjectLocator.hasRootProjectConfiguration(at: path, fileManager: fileManager) {
                return .success(nativeMiniAppSnapshot())
            }
            return .failure(.missingDevelopmentScript(type))
        }

        let selectedMode = selectedStartupMode(from: startupModes)
        return .success(
            ProjectCommandSnapshot(
                startCommand: selectedMode.startCommand,
                startupModes: startupModes,
                selectedStartupModeID: selectedMode.id,
                buildCommand: commandForFirstScript(
                    buildScriptNames,
                    packageManager: packageManager,
                    manifest: manifest
                ) ?? "",
                cleanCommand: commandForScript("clean", packageManager: packageManager, manifest: manifest) ?? "",
                installCommand: packageManager.installCommand,
                stopCommand: ProjectCommandSnapshot.managedStopCommand,
                discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
                commandProfileName: "自动识别 · \(profileName) + \(packageManager.rawValue)",
                installStrategy: .ifMissing
            )
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
        let startupSnapshot = preferredStartupSnapshot(primary: legacy, fallback: builtin)
        return ProjectCommandSnapshot(
            startCommand: startupSnapshot.startCommand,
            startupModes: startupSnapshot.startupModes,
            selectedStartupModeID: startupSnapshot.selectedStartupModeID,
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

    private static func nativeMiniAppSnapshot() -> ProjectCommandSnapshot {
        ProjectCommandSnapshot(
            startCommand: "",
            startupModes: [],
            selectedStartupModeID: nil,
            buildCommand: "",
            cleanCommand: "",
            installCommand: "",
            stopCommand: "",
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · 原生微信小程序",
            installStrategy: .never,
            runtimeKind: .weChatNative
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
        guard let script = manifest?.scripts?[name],
              script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return packageManager.runCommand(name)
    }

    private static func detectedStartupModes(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> [ProjectStartupMode] {
        let preferredNames = ["dev", "dev:mock", "dev:live"]
        let additionalNames = manifest?.nonemptyScriptNames
            .filter { $0.hasPrefix("dev:") && preferredNames.contains($0) == false }
            .sorted() ?? []
        return startupModes(
            scriptNames: preferredNames + additionalNames + ["mock", "start", "serve"],
            packageManager: packageManager,
            manifest: manifest
        )
    }

    private static func detectedMiniAppStartupModes(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest
    ) -> [ProjectStartupMode] {
        let preferredNames = [
            "dev:weapp",
            "dev:mp-weixin",
            "dev:mp",
            "serve:wx"
        ]
        let additionalNames = manifest.nonemptyScriptNames
            .filter { name in
                (name.hasPrefix("dev:weapp:") ||
                    name.hasPrefix("dev:mp-weixin:") ||
                    name.hasPrefix("dev:mp:") ||
                    name.hasPrefix("serve:wx:")) &&
                    preferredNames.contains(name) == false
            }
            .sorted()
        let platformModes = startupModes(
            scriptNames: preferredNames + additionalNames,
            packageManager: packageManager,
            manifest: manifest
        )
        if platformModes.isEmpty == false {
            return platformModes
        }

        return startupModes(
            scriptNames: ["serve", "dev", "start"],
            packageManager: packageManager,
            manifest: manifest
        )
    }

    private static func startupModes(
        scriptNames: [String],
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> [ProjectStartupMode] {
        scriptNames.compactMap { scriptName in
            guard commandForScript(scriptName, packageManager: packageManager, manifest: manifest) != nil else {
                return nil
            }
            return ProjectStartupMode(
                id: scriptName,
                displayName: startupModeDisplayName(scriptName),
                startCommand: packageManager.runCommand(scriptName),
                source: .autoDetected
            )
        }
    }

    private static func startupModeDisplayName(_ scriptName: String) -> String {
        switch scriptName {
        case "dev", "dev:weapp", "dev:mp-weixin", "dev:mp", "serve:wx", "serve":
            return "默认"
        case "dev:mock", "mock":
            return "Mock"
        case "dev:live":
            return "Live"
        case "start":
            return "Start"
        default:
            return scriptName.split(separator: ":").dropFirst().joined(separator: ":")
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

    private static func preferredStartupSnapshot(
        primary: ProjectCommandSnapshot,
        fallback: ProjectCommandSnapshot
    ) -> ProjectCommandSnapshot {
        let trimmedPrimaryStartCommand = primary.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrimaryStartCommand.isEmpty ? fallback : primary
    }

    private static func detectPackageManager(
        at path: String,
        manifest: PackageManifest?,
        fileManager: FileManager,
        defaultPackageManager: ProjectPackageManager = .pnpm
    ) -> ProjectPackageManager {
        if let rawPackageManager = manifest?.packageManager?.split(separator: "@").first,
           let packageManager = ProjectPackageManager(rawValue: String(rawPackageManager)) {
            return packageManager
        }

        let rootManifest = loadManifest(at: path)
        if let rawPackageManager = rootManifest?.packageManager?.split(separator: "@").first,
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

        return defaultPackageManager
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

    private static func miniAppFrameworkName(_ manifest: PackageManifest) -> String {
        if manifest.hasDependency(named: "@tarojs/cli") ||
            manifest.hasDependency(named: "@tarojs/runtime") ||
            manifest.scriptValues.contains(where: { $0.localizedCaseInsensitiveContains("taro build") }) {
            return "Taro"
        }
        if manifest.hasDependency(named: "@dcloudio/uni-app") ||
            manifest.scriptValues.contains(where: { $0.localizedCaseInsensitiveContains("uni -p mp-weixin") }) {
            return "UniApp"
        }
        if manifest.hasDependency(named: "@mpxjs/core") ||
            manifest.hasDependency(named: "@mpxjs/mpx-cli-service") ||
            manifest.scriptValues.contains(where: { $0.localizedCaseInsensitiveContains("mpx-cli-service") }) {
            return "Mpx"
        }
        return "微信小程序"
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

    var nonemptyScriptNames: [String] {
        (scripts ?? [:]).compactMap { name, command in
            command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        }
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
        ProjectPath.canonical(path)
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
            lhs.preparedDependencyFingerprint != rhs.preparedDependencyFingerprint ||
            lhs.runtimeKind != rhs.runtimeKind ||
            lhs.commandConfigId != rhs.commandConfigId ||
            lhs.availableStartupModes != rhs.availableStartupModes ||
            lhs.selectedStartupModeID != rhs.selectedStartupModeID
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
