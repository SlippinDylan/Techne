import Foundation

struct ProjectProcessSnapshot: Sendable, Equatable {
    let pid: Int32
    let processGroupID: Int32
    let commandLine: String
    let currentWorkingDirectory: String?
}

enum ProjectProcessScope {
    static func contains(process: ProjectProcessSnapshot, projectRootPath: String) -> Bool {
        let normalizedProjectRoot = DevServerProjectMatcher.normalize(projectRootPath)

        if let currentWorkingDirectory = process.currentWorkingDirectory {
            return DevServerProjectMatcher.belongs(
                serverPath: currentWorkingDirectory,
                toProjectPath: normalizedProjectRoot
            )
        }

        return commandLineContainsProjectPath(
            process.commandLine,
            normalizedProjectRoot: normalizedProjectRoot
        )
    }

    private static func commandLineContainsProjectPath(
        _ commandLine: String,
        normalizedProjectRoot: String
    ) -> Bool {
        guard normalizedProjectRoot.isEmpty == false else { return false }

        let escapedPath = NSRegularExpression.escapedPattern(for: normalizedProjectRoot)
        let pattern = #"(^|[\s'"=:(])\#(escapedPath)(?=$|[\s\/"'.,):])"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        let range = NSRange(commandLine.startIndex..<commandLine.endIndex, in: commandLine)
        return regex.firstMatch(in: commandLine, options: [], range: range) != nil
    }
}
