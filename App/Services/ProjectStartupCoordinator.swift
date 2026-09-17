import Foundation

enum ProjectStartupStage: String, Equatable, Sendable {
    case install
    case clean
    case start
}

enum ProjectStartupEvent: Equatable, Sendable {
    case phaseStarted(ProjectStartupStage)
    case dependenciesInstalled
    case startCommandStarted(pid: Int32)
}

enum ProjectStartupPhase: Equatable, Sendable {
    case install(command: String)
    case clean(command: String)
    case start(command: String)

    var command: String {
        switch self {
        case .install(let command), .clean(let command), .start(let command):
            return command
        }
    }

    var stage: ProjectStartupStage {
        switch self {
        case .install:
            return .install
        case .clean:
            return .clean
        case .start:
            return .start
        }
    }
}

struct ProjectStartupPlan: Equatable, Sendable {
    let phases: [ProjectStartupPhase]
    let messages: [String]
    let shellScript: String
    let shouldInstallDependencies: Bool
    let dependencyFingerprint: String?
}

struct ProjectStartupCoordinator {
    nonisolated static let startPhaseMessagePrefix = "[系统] 准备启动命令: "
    nonisolated static let installCompletedMessage = "[系统] 依赖安装完成"
    nonisolated static let controlSignalPrefix = "__TECHNE_STARTUP_PHASE__:"

    static func shouldInstallDependencies(
        for project: Project,
        fileManager: FileManager = .default
    ) -> Bool {
        let installCommand = project.installCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !installCommand.isEmpty else { return false }

        switch project.installStrategy {
        case .never:
            return false
        case .always:
            return true
        case .ifMissing:
            let state = ProjectDependencyResolver.state(at: project.path, fileManager: fileManager)
            guard state.fingerprint != nil else { return false }
            guard state.hasInstallArtifact else { return true }
            guard let preparedFingerprint = project.preparedDependencyFingerprint else { return false }
            return state.fingerprint != preparedFingerprint
        }
    }

    static func makePlan(
        for project: Project,
        fallbackCleanCommand: String,
        includesClean: Bool = false,
        fileManager: FileManager = .default
    ) -> ProjectStartupPlan {
        let installCommand = project.installCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommand = project.cleanCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let startCommand = project.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackCleanCommand = fallbackCleanCommand.trimmingCharacters(in: .whitespacesAndNewlines)

        let shouldInstall = shouldInstallDependencies(for: project, fileManager: fileManager)
        let dependencyState = ProjectDependencyResolver.state(at: project.path, fileManager: fileManager)
        var phases: [ProjectStartupPhase] = []

        if shouldInstall {
            let workspaceRootPath = dependencyState.workspaceRootPath
            let command: String
            if ProjectPath.canonical(workspaceRootPath) == ProjectPath.canonical(project.path) {
                command = installCommand
            } else {
                command = "(cd \(ShellEscape.escape(workspaceRootPath)) && \(installCommand))"
            }
            phases.append(.install(command: command))
        }

        if includesClean {
            let resolvedCleanCommand = cleanCommand.isEmpty ? fallbackCleanCommand : cleanCommand
            if !resolvedCleanCommand.isEmpty {
                phases.append(.clean(command: resolvedCleanCommand))
            }
        }

        phases.append(.start(command: startCommand))

        let messages = installMessages(
            for: project,
            shouldInstall: shouldInstall,
            installCommand: installCommand
        )

        return ProjectStartupPlan(
            phases: phases,
            messages: messages,
            shellScript: buildShellScript(for: project.path, phases: phases, messages: messages),
            shouldInstallDependencies: shouldInstall,
            dependencyFingerprint: dependencyState.fingerprint
        )
    }

    nonisolated static func containsStartPhaseMessage(_ output: String) -> Bool {
        output.contains(startPhaseMessagePrefix)
    }

    nonisolated static func event(forControlLine line: String) -> ProjectStartupEvent? {
        guard let markerRange = line.range(of: controlSignalPrefix) else { return nil }
        let suffix = line[markerRange.upperBound...]
        let rawStage = suffix.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if rawStage == "install-completed" {
            return .dependenciesInstalled
        }
        guard let stage = ProjectStartupStage(rawValue: rawStage) else { return nil }
        return .phaseStarted(stage)
    }

    private static func installMessages(
        for project: Project,
        shouldInstall: Bool,
        installCommand: String
    ) -> [String] {
        guard shouldInstall else { return [] }

        let installMessage: String
        switch project.installStrategy {
        case .ifMissing:
            installMessage = "[系统] 检测到缺少依赖，准备执行安装命令: \(installCommand)"
        case .always:
            installMessage = "[系统] 根据安装策略，准备执行安装命令: \(installCommand)"
        case .never:
            installMessage = "[系统] 准备执行安装命令: \(installCommand)"
        }

        return [
            "[系统] 正在检查依赖...",
            installMessage
        ]
    }

    private static func buildShellScript(
        for path: String,
        phases: [ProjectStartupPhase],
        messages: [String]
    ) -> String {
        var lines = [
            "set -e",
            "cd \(ShellEscape.escape(path))"
        ]

        lines.append(contentsOf: messages.map(shellPrintLine))

        for phase in phases {
            lines.append(controlSignalLine(for: phase.stage))

            switch phase {
            case .install(let command):
                lines.append(command)
                lines.append(shellPrintLine("\(controlSignalPrefix)install-completed"))
                lines.append(shellPrintLine(installCompletedMessage))
            case .clean(let command):
                lines.append(command)
            case .start(let command):
                lines.append(shellPrintLine("\(startPhaseMessagePrefix)\(command)"))
                lines.append(command)
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func shellPrintLine(_ message: String) -> String {
        "printf '%s\\n' \(ShellEscape.escape(message))"
    }

    private static func controlSignalLine(for stage: ProjectStartupStage) -> String {
        shellPrintLine("\(controlSignalPrefix)\(stage.rawValue)")
    }
}
