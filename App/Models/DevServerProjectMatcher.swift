import Foundation

enum DevServerProjectMatcher {
    nonisolated static func normalize(_ path: String) -> String {
        ProjectPath.canonical(path)
    }

    nonisolated static func belongs(serverPath: String, toProjectPath projectPath: String) -> Bool {
        let normalizedServerPath = normalize(serverPath)
        let normalizedProjectPath = normalize(projectPath)

        if normalizedServerPath == normalizedProjectPath {
            return true
        }

        let projectPrefix = normalizedProjectPath == "/" ? "/" : normalizedProjectPath + "/"
        return normalizedServerPath.hasPrefix(projectPrefix)
    }

    nonisolated static func bestMatchingProjectPath(
        for server: DevServer,
        managedProjectPaths: [String]
    ) -> String? {
        bestMatchingProjectPath(
            forServerPath: server.projectPath,
            managedProjectPaths: managedProjectPaths
        )
    }

    nonisolated static func bestMatchingProjectPath(
        forServerPath serverPath: String,
        managedProjectPaths: [String]
    ) -> String? {
        managedProjectPaths
            .map(normalize)
            .filter { belongs(serverPath: serverPath, toProjectPath: $0) }
            .max(by: { $0.count < $1.count })
    }

}
