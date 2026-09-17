import Foundation

enum WeChatProjectLocator {
    static func developerToolsProjectPath(
        for projectPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        let rootURL = URL(fileURLWithPath: ProjectPath.canonical(projectPath), isDirectory: true)
        let candidates = [
            rootURL,
            rootURL.appendingPathComponent("dist", isDirectory: true),
            rootURL.appendingPathComponent("dist/weapp", isDirectory: true),
            rootURL.appendingPathComponent("dist/dev/mp-weixin", isDirectory: true),
            rootURL.appendingPathComponent("unpackage/dist/dev/mp-weixin", isDirectory: true)
        ]

        return candidates.first { directoryURL in
            hasValidProjectConfiguration(at: directoryURL, fileManager: fileManager)
        }?.path
    }

    static func hasRootProjectConfiguration(
        at projectPath: String,
        fileManager: FileManager = .default
    ) -> Bool {
        hasValidProjectConfiguration(
            at: URL(fileURLWithPath: ProjectPath.canonical(projectPath), isDirectory: true),
            fileManager: fileManager
        )
    }

    private static func hasValidProjectConfiguration(
        at directoryURL: URL,
        fileManager: FileManager
    ) -> Bool {
        let configurationURL = directoryURL.appendingPathComponent("project.config.json")
        guard fileManager.fileExists(atPath: configurationURL.path),
              let data = try? Data(contentsOf: configurationURL),
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
