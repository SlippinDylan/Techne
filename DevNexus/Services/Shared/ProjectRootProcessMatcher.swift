import Foundation

struct ProjectProcessSnapshot: Sendable, Equatable {
    let pid: Int32
    let processGroupID: Int32
    let commandLine: String
    let currentWorkingDirectory: String?
}

struct ProjectRootStopPlan: Sendable, Equatable {
    let matchedPIDs: [Int32]
    let processGroupIDs: [Int32]
    let fallbackProcessIDs: [Int32]

    var isEmpty: Bool {
        processGroupIDs.isEmpty && fallbackProcessIDs.isEmpty
    }
}

enum ProjectRootProcessMatcher {
    static func matches(process: ProjectProcessSnapshot, projectRootPath: String) -> Bool {
        let normalizedProjectRoot = DevServerProjectMatcher.normalize(projectRootPath)

        if let currentWorkingDirectory = process.currentWorkingDirectory,
           DevServerProjectMatcher.belongs(serverPath: currentWorkingDirectory, toProjectPath: normalizedProjectRoot) {
            return true
        }

        return commandLineContainsProjectPath(
            process.commandLine,
            normalizedProjectRoot: normalizedProjectRoot
        )
    }

    static func stopPlan(
        forProjectRootPath projectRootPath: String,
        processes: [ProjectProcessSnapshot]
    ) -> ProjectRootStopPlan {
        let matchedProcesses = processes.filter {
            matches(process: $0, projectRootPath: projectRootPath)
        }

        var seenGroupIDs = Set<Int32>()
        var processGroupIDs: [Int32] = []
        var seenFallbackPIDs = Set<Int32>()
        var fallbackProcessIDs: [Int32] = []

        for process in matchedProcesses {
            if process.processGroupID > 0 {
                if seenGroupIDs.insert(process.processGroupID).inserted {
                    processGroupIDs.append(process.processGroupID)
                }
                continue
            }

            if seenFallbackPIDs.insert(process.pid).inserted {
                fallbackProcessIDs.append(process.pid)
            }
        }

        return ProjectRootStopPlan(
            matchedPIDs: matchedProcesses.map(\.pid),
            processGroupIDs: processGroupIDs,
            fallbackProcessIDs: fallbackProcessIDs
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
