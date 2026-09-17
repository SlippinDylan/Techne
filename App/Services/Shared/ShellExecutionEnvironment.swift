import Foundation

enum ShellExecutionEnvironment {
    private nonisolated static let supportedShellNames: Set<String> = ["zsh", "bash", "fish"]
    private nonisolated static let fallbackShellURL = URL(fileURLWithPath: "/bin/zsh")

    nonisolated static func shellURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        guard let configuredPath = environment["SHELL"],
              configuredPath.hasPrefix("/"),
              supportedShellNames.contains(URL(fileURLWithPath: configuredPath).lastPathComponent),
              fileManager.isExecutableFile(atPath: configuredPath) else {
            return fallbackShellURL
        }
        return URL(fileURLWithPath: configuredPath)
    }

    nonisolated static func arguments(for command: String) -> [String] {
        ["-l", "-i", "-c", command]
    }
}
