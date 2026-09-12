import Foundation

enum SystemProcessInspector {
    nonisolated static let processListArguments = ["-axww", "-o", "pid=,pgid=,command="]
    nonisolated static let commandLineArgumentsPrefix = ["-p"]
    nonisolated static let commandLineArgumentsSuffix = ["-ww", "-o", "command="]
    nonisolated static let listeningTCPArguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P"]

    nonisolated private static let lsofExecutableCandidates = [
        "/usr/sbin/lsof",
        "/usr/bin/lsof"
    ]

    nonisolated static func resolveLsofExecutableURL() -> URL? {
        let fileManager = FileManager.default

        for candidate in lsofExecutableCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }

    nonisolated static func makeProcessListTask() -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = processListArguments
        return task
    }

    nonisolated static func makeCommandLineTask(pid: Int32) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = commandLineArgumentsPrefix + [String(pid)] + commandLineArgumentsSuffix
        return task
    }

    nonisolated static func makeCurrentWorkingDirectoryTask(pid: Int32? = nil) -> Process? {
        guard let lsofExecutableURL = resolveLsofExecutableURL() else {
            return nil
        }

        let task = Process()
        task.executableURL = lsofExecutableURL

        if let pid {
            task.arguments = ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
        } else {
            task.arguments = ["-Fn", "-d", "cwd"]
        }

        return task
    }

    nonisolated static func makeListeningTCPTask() -> Process? {
        guard let lsofExecutableURL = resolveLsofExecutableURL() else {
            return nil
        }

        let task = Process()
        task.executableURL = lsofExecutableURL
        task.arguments = listeningTCPArguments
        return task
    }

    nonisolated static func makeListeningPortTask(port: Int) -> Process? {
        guard let lsofExecutableURL = resolveLsofExecutableURL() else {
            return nil
        }

        let task = Process()
        task.executableURL = lsofExecutableURL
        task.arguments = ["-i", ":\(port)", "-sTCP:LISTEN"]
        return task
    }

    nonisolated static func parseProcessSnapshots(
        from output: String,
        currentWorkingDirectories: [Int32: String]
    ) -> [ProjectProcessSnapshot] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseProcessSnapshot(from: String($0), currentWorkingDirectories: currentWorkingDirectories) }
    }

    nonisolated static func parseProcessSnapshot(
        from line: String,
        currentWorkingDirectories: [Int32: String]
    ) -> ProjectProcessSnapshot? {
        let components = line.split(maxSplits: 2, omittingEmptySubsequences: true) { $0.isWhitespace }
        guard components.count == 3,
              let pid = Int32(components[0]),
              let processGroupID = Int32(components[1]) else {
            return nil
        }

        return ProjectProcessSnapshot(
            pid: pid,
            processGroupID: processGroupID,
            commandLine: String(components[2]),
            currentWorkingDirectory: currentWorkingDirectories[pid]
        )
    }

    nonisolated static func parseCurrentWorkingDirectories(from output: String) -> [Int32: String] {
        var directoriesByPID: [Int32: String] = [:]
        var currentPID: Int32?

        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentPID = pid
                continue
            }

            if line.hasPrefix("n"), let currentPID {
                directoriesByPID[currentPID] = String(line.dropFirst())
            }
        }

        return directoriesByPID
    }
}
