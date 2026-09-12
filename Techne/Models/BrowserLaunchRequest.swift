import Foundation

struct BrowserLaunchTarget: Sendable, Equatable {
    let launchSource: String
    let serverPort: Int
    let projectPath: String?

    nonisolated init(launchSource: String, serverPort: Int, projectPath: String?) {
        self.launchSource = launchSource
        self.serverPort = serverPort
        self.projectPath = Self.normalizeProjectPath(projectPath)
    }

    nonisolated var associationKey: String {
        "\(launchSource):\(serverPort):\(projectPath ?? "")"
    }

    nonisolated func matches(server: DevServer) -> Bool {
        guard serverPort == server.port else {
            return false
        }

        guard let projectPath else {
            return true
        }

        guard let normalizedServerPath = Self.normalizeProjectPath(server.projectPath) else {
            return true
        }

        return projectPath == normalizedServerPath
    }

    private nonisolated static func normalizeProjectPath(_ path: String?) -> String? {
        guard let path else { return nil }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        return URL(fileURLWithPath: trimmedPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}

struct BrowserLaunchRequest: Sendable, Equatable {
    let browser: Browser
    let url: String?
    let profileDirectoryName: String
    let opensInNewInstance: Bool
    let tracksInstance: Bool
    let requestedDebugPort: Int?
    let launchSource: String
    let launchTarget: BrowserLaunchTarget?
    let launchKey: String

    var normalizedURL: String? {
        guard let url else { return nil }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return nil }

        if trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") {
            return trimmedURL
        }

        return "http://\(trimmedURL)"
    }
}

extension BrowserLaunchRequest {
    static func devServer(
        browser: Browser,
        port: Int,
        projectPath: String?,
        shouldOpenURL: Bool,
        launchSource: String
    ) -> BrowserLaunchRequest {
        let launchTarget = BrowserLaunchTarget(
            launchSource: launchSource,
            serverPort: port,
            projectPath: projectPath
        )

        return BrowserLaunchRequest(
            browser: browser,
            url: shouldOpenURL ? "http://localhost:\(port)" : nil,
            profileDirectoryName: "dev-server-\(port)",
            opensInNewInstance: browser.type.supportsNewApplicationInstance,
            tracksInstance: browser.type.supportsManagedInstances,
            requestedDebugPort: browser.type.supportsRemoteDebugging ? AppConfig.Browser.defaultDebugPort : nil,
            launchSource: launchSource,
            launchTarget: launchTarget,
            launchKey: "\(launchTarget.associationKey):\(browser.type.bundleId)"
        )
    }

    static func manual(
        browser: Browser,
        url: String?,
        launchSource: String
    ) -> BrowserLaunchRequest {
        BrowserLaunchRequest(
            browser: browser,
            url: url,
            profileDirectoryName: "manual-browser-instance",
            opensInNewInstance: browser.type.supportsNewApplicationInstance,
            tracksInstance: browser.type.supportsManagedInstances,
            requestedDebugPort: browser.type.supportsRemoteDebugging ? AppConfig.Browser.defaultDebugPort : nil,
            launchSource: launchSource,
            launchTarget: nil,
            launchKey: "\(launchSource):manual:\(browser.type.bundleId)"
        )
    }
}
