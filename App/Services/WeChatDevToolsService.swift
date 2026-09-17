import Foundation

enum WeChatDevToolsError: LocalizedError, Equatable, Sendable {
    case cliNotFound
    case projectConfigurationNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "未找到微信开发者工具 CLI，请确认已安装微信开发者工具"
        case .projectConfigurationNotFound:
            return "未找到可供微信开发者工具打开的 project.config.json"
        case .commandFailed(let output):
            return output.isEmpty ? "微信开发者工具未能重建文件监听" : output
        }
    }
}

struct WeChatDevToolsResetPlan: Equatable, Sendable {
    let executableURL: URL
    let projectPath: String

    var arguments: [String] {
        ["reset-fileutils", "--project", projectPath]
    }
}

struct WeChatDevToolsService: Sendable {
    private let fileManager: FileManager
    private let applicationDirectories: [URL]

    init(
        fileManager: FileManager = .default,
        applicationDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    func makeResetPlan(for projectPath: String) -> Result<WeChatDevToolsResetPlan, WeChatDevToolsError> {
        guard let executableURL = cliURL() else {
            return .failure(.cliNotFound)
        }
        guard let resolvedProjectPath = developerToolsProjectPath(for: projectPath) else {
            return .failure(.projectConfigurationNotFound)
        }
        return .success(
            WeChatDevToolsResetPlan(
                executableURL: executableURL,
                projectPath: resolvedProjectPath
            )
        )
    }

    func resetFileWatching(for projectPath: String) async -> Result<String, WeChatDevToolsError> {
        let plan: WeChatDevToolsResetPlan
        switch makeResetPlan(for: projectPath) {
        case .success(let resolvedPlan):
            plan = resolvedPlan
        case .failure(let error):
            return .failure(error)
        }

        let process = Process()
        process.executableURL = plan.executableURL
        process.arguments = plan.arguments

        do {
            let result = try await ProcessUtils.runAndCapture(process)
            let output = [result.standardOutput, result.standardError]
                .compactMap { String(data: $0, encoding: .utf8) }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.terminationStatus == 0 else {
                return .failure(.commandFailed(output))
            }
            return .success(output)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    private func cliURL() -> URL? {
        let preferredAppNames = ["wechatwebdevtools.app", "微信开发者工具.app"]
        for directory in applicationDirectories {
            for appName in preferredAppNames {
                let cliURL = directory
                    .appendingPathComponent(appName, isDirectory: true)
                    .appendingPathComponent("Contents/MacOS/cli")
                if fileManager.isExecutableFile(atPath: cliURL.path) {
                    return cliURL
                }
            }

            guard let appURLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for appURL in appURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where appURL.pathExtension == "app" {
                let name = appURL.deletingPathExtension().lastPathComponent.lowercased()
                guard name.contains("wechat") || name.contains("weixin") || name.contains("微信") else {
                    continue
                }
                let cliURL = appURL.appendingPathComponent("Contents/MacOS/cli")
                if fileManager.isExecutableFile(atPath: cliURL.path) {
                    return cliURL
                }
            }
        }
        return nil
    }

    private func developerToolsProjectPath(for projectPath: String) -> String? {
        let rootURL = URL(fileURLWithPath: ProjectPath.canonical(projectPath), isDirectory: true)
        let candidates = [
            rootURL,
            rootURL.appendingPathComponent("dist", isDirectory: true),
            rootURL.appendingPathComponent("dist/weapp", isDirectory: true),
            rootURL.appendingPathComponent("dist/dev/mp-weixin", isDirectory: true),
            rootURL.appendingPathComponent("unpackage/dist/dev/mp-weixin", isDirectory: true)
        ]

        return candidates.first(where: hasValidProjectConfiguration(at:))?.path
    }

    private func hasValidProjectConfiguration(at directoryURL: URL) -> Bool {
        let configurationURL = directoryURL.appendingPathComponent("project.config.json")
        guard let data = try? Data(contentsOf: configurationURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appID = object["appid"] as? String,
              appID.isEmpty == false,
              let projectName = object["projectname"] as? String,
              projectName.isEmpty == false else {
            return false
        }
        return true
    }
}
