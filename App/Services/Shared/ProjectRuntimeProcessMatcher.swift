import Foundation

struct ProjectRuntimeProcessMatch: Equatable, Sendable {
    let representativePID: Int32
    let processGroupIDs: [Int32]
}

enum ProjectRuntimeProcessMatcher {
    nonisolated private static let ignoredCommandTokens: Set<String> = [
        "&&", "||", ";", "run", "exec", "--"
    ]

    nonisolated static func matches(
        for project: Project,
        in snapshots: [ProjectProcessSnapshot]
    ) -> ProjectRuntimeProcessMatch? {
        guard project.runtimeKind == .shell else {
            return nil
        }

        let scopedSnapshots = snapshots.filter { snapshot in
            guard let currentWorkingDirectory = snapshot.currentWorkingDirectory else {
                return false
            }
            return DevServerProjectMatcher.belongs(
                serverPath: currentWorkingDirectory,
                toProjectPath: project.path
            )
        }
        guard scopedSnapshots.isEmpty == false else {
            return nil
        }

        let signatureTokens = commandSignatureTokens(project.startCommand)
        guard signatureTokens.isEmpty == false else {
            return nil
        }

        let groupedSnapshots = Dictionary(grouping: scopedSnapshots) { snapshot in
            snapshot.processGroupID > 0 ? snapshot.processGroupID : snapshot.pid
        }
        let matchingGroups = groupedSnapshots.filter { _, group in
            group.contains { snapshot in
                commandLine(snapshot.commandLine, contains: signatureTokens)
            }
        }
        guard matchingGroups.isEmpty == false else {
            return nil
        }

        let processGroupIDs = matchingGroups.keys.sorted()
        guard let selectedGroupID = processGroupIDs.last,
              let selectedGroup = matchingGroups[selectedGroupID] else {
            return nil
        }
        let representativePID = selectedGroup.first(where: { $0.pid == selectedGroupID })?.pid
            ?? selectedGroup.first(where: {
                commandLine($0.commandLine, contains: signatureTokens)
            })?.pid
            ?? selectedGroup.map(\.pid).max()
        guard let representativePID else {
            return nil
        }

        return ProjectRuntimeProcessMatch(
            representativePID: representativePID,
            processGroupIDs: processGroupIDs
        )
    }

    nonisolated static func reconcile(
        projects: [Project],
        snapshots: [ProjectProcessSnapshot]
    ) -> [UUID: ProjectRuntimeProcessMatch] {
        Dictionary(uniqueKeysWithValues: projects.compactMap { project in
            matches(for: project, in: snapshots).map { (project.id, $0) }
        })
    }

    private nonisolated static func commandSignatureTokens(_ command: String) -> [String] {
        command
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .map(normalizeCommandToken)
            .filter { token in
                token.isEmpty == false
                    && token.hasPrefix("-") == false
                    && token.contains("=") == false
                    && ignoredCommandTokens.contains(token.lowercased()) == false
            }
    }

    private nonisolated static func commandLine(
        _ commandLine: String,
        contains signatureTokens: [String]
    ) -> Bool {
        let commandTokens = Set(commandLine.split(whereSeparator: { $0.isWhitespace }).map {
            normalizeCommandToken(String($0))
        })
        return signatureTokens.allSatisfy(commandTokens.contains)
    }

    private nonisolated static func normalizeCommandToken(_ token: String) -> String {
        let trimmedToken = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        let basename = URL(fileURLWithPath: trimmedToken).lastPathComponent.lowercased()

        switch basename {
        case "npm-cli.js":
            return "npm"
        case "npx-cli.js":
            return "npx"
        case "pnpm.cjs", "pnpm.js":
            return "pnpm"
        case "yarn.js", "yarn.cjs":
            return "yarn"
        default:
            return basename
        }
    }
}
