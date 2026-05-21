import Darwin
import Foundation

struct BrowserInstanceStore: Sendable {
    let rootDirectoryURL: URL

    private enum InstanceRecordLoadError: Error {
        case invalidConfig
    }

    nonisolated init(
        rootDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".devnexus-browsers", isDirectory: true)
    ) {
        self.rootDirectoryURL = rootDirectoryURL
    }

    nonisolated var profilesDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("profiles", isDirectory: true)
    }

    nonisolated func makeUniqueProfileDirectory(named baseName: String) throws -> URL {
        try ensureBaseDirectories()

        let safeBaseName = sanitizeFileNameComponent(baseName)
        let profileDirectoryURL = profilesDirectoryURL
            .appendingPathComponent("\(safeBaseName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectoryURL, withIntermediateDirectories: true)
        return profileDirectoryURL
    }

    nonisolated func save(_ record: BrowserInstanceRecord) throws {
        try ensureBaseDirectories()

        try serializedConfig(for: record).write(
            to: configFileURL(for: record.instanceName),
            atomically: true,
            encoding: .utf8
        )

        try "\(record.pid)".write(
            to: pidFileURL(for: record.instanceName),
            atomically: true,
            encoding: .utf8
        )
    }

    nonisolated func loadTrackedInstances() throws -> [BrowserInstanceRecord] {
        try ensureBaseDirectories()

        let pidFiles = try FileManager.default.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "pid" }

        var records: [BrowserInstanceRecord] = []

        for pidFileURL in pidFiles {
            guard let instanceName = pidFileURL.deletingPathExtension().lastPathComponent.nilIfEmpty else {
                continue
            }

            guard let pidString = try? String(contentsOf: pidFileURL, encoding: .utf8),
                  let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                try? removeTrackedInstance(
                    named: instanceName,
                    profileDirectoryPath: readProfileDirectoryPathIfPresent(for: instanceName) ?? ""
                )
                continue
            }

            guard isProcessRunning(pid: pid) else {
                let staleProfileDirectoryPath = readProfileDirectoryPathIfPresent(for: instanceName)
                try? removeTrackedInstance(
                    named: instanceName,
                    profileDirectoryPath: staleProfileDirectoryPath ?? ""
                )
                continue
            }

            do {
                records.append(try loadTrackedInstance(named: instanceName, pid: pid))
            } catch {
                try? removeTrackedInstance(
                    named: instanceName,
                    profileDirectoryPath: readProfileDirectoryPathIfPresent(for: instanceName) ?? ""
                )
            }
        }

        return records.sorted { $0.startedAt > $1.startedAt }
    }

    nonisolated func removeTrackedInstance(named instanceName: String, profileDirectoryPath: String) throws {
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: pidFileURL(for: instanceName))
        try? fileManager.removeItem(at: configFileURL(for: instanceName))

        guard !profileDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let profileURL = URL(fileURLWithPath: profileDirectoryPath)
        if fileManager.fileExists(atPath: profileURL.path) {
            try? fileManager.removeItem(at: profileURL)
        }
    }

    private nonisolated func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
    }

    private nonisolated func pidFileURL(for instanceName: String) -> URL {
        rootDirectoryURL.appendingPathComponent("\(instanceName).pid")
    }

    private nonisolated func configFileURL(for instanceName: String) -> URL {
        rootDirectoryURL.appendingPathComponent("\(instanceName).config")
    }

    private nonisolated func serializedConfig(for record: BrowserInstanceRecord) -> String {
        let formatter = ISO8601DateFormatter()

        return [
            "INSTANCE_NAME=\"\(record.instanceName)\"",
            "INSTANCE_BROWSER_NAME=\"\(record.browserName)\"",
            "INSTANCE_BROWSER_BUNDLE_ID=\"\(record.browserBundleID)\"",
            "INSTANCE_BROWSER_APP_PATH=\"\(record.browserAppPath)\"",
            "INSTANCE_URL=\"\(record.launchedURL)\"",
            "INSTANCE_DEBUG_PORT=\"\(record.debugPort.map(String.init) ?? "")\"",
            "INSTANCE_PROFILE_DIR=\"\(record.profileDirectoryPath)\"",
            "INSTANCE_STARTED_AT=\"\(formatter.string(from: record.startedAt))\"",
            "INSTANCE_LAUNCH_SOURCE=\"\(record.launchTarget?.launchSource ?? "")\"",
            "INSTANCE_TARGET_SERVER_PORT=\"\(record.launchTarget.map { String($0.serverPort) } ?? "")\"",
            "INSTANCE_TARGET_PROJECT_PATH=\"\(record.launchTarget?.projectPath ?? "")\""
        ]
        .joined(separator: "\n")
    }

    private nonisolated func loadTrackedInstance(named instanceName: String, pid: Int32) throws -> BrowserInstanceRecord {
        let config = try String(contentsOf: configFileURL(for: instanceName), encoding: .utf8)
        return try parseRecord(instanceName: instanceName, pid: pid, config: config)
    }

    private nonisolated func parseRecord(instanceName: String, pid: Int32, config: String) throws -> BrowserInstanceRecord {
        let formatter = ISO8601DateFormatter()
        let browserAppPath = configValue(for: "INSTANCE_BROWSER_APP_PATH", in: config)
            .nilIfEmpty
            ?? configValue(for: "INSTANCE_BROWSER_PATH", in: config).nilIfEmpty
        let startedAt = formatter.date(from: configValue(for: "INSTANCE_STARTED_AT", in: config))
            ?? extractStartTime(from: instanceName)
        guard let profileDirectoryPath = configValue(for: "INSTANCE_PROFILE_DIR", in: config).nilIfEmpty else {
            throw InstanceRecordLoadError.invalidConfig
        }
        let launchTarget = makeLaunchTarget(from: config)

        return BrowserInstanceRecord(
            instanceName: instanceName,
            pid: pid,
            browserName: configValue(for: "INSTANCE_BROWSER_NAME", in: config).nilIfEmpty
                ?? extractBrowserName(from: browserAppPath ?? ""),
            browserBundleID: configValue(for: "INSTANCE_BROWSER_BUNDLE_ID", in: config),
            browserAppPath: browserAppPath ?? "",
            launchedURL: configValue(for: "INSTANCE_URL", in: config),
            debugPort: Int(configValue(for: "INSTANCE_DEBUG_PORT", in: config)),
            profileDirectoryPath: profileDirectoryPath,
            startedAt: startedAt,
            launchTarget: launchTarget
        )
    }

    private nonisolated func readProfileDirectoryPathIfPresent(for instanceName: String) -> String? {
        guard let config = try? String(contentsOf: configFileURL(for: instanceName), encoding: .utf8) else {
            return nil
        }

        return configValue(for: "INSTANCE_PROFILE_DIR", in: config).nilIfEmpty
    }

    private nonisolated func makeLaunchTarget(from config: String) -> BrowserLaunchTarget? {
        guard let launchSource = configValue(for: "INSTANCE_LAUNCH_SOURCE", in: config).nilIfEmpty,
              let serverPort = Int(configValue(for: "INSTANCE_TARGET_SERVER_PORT", in: config))
        else {
            return nil
        }

        return BrowserLaunchTarget(
            launchSource: launchSource,
            serverPort: serverPort,
            projectPath: configValue(for: "INSTANCE_TARGET_PROJECT_PATH", in: config).nilIfEmpty
        )
    }

    private nonisolated func configValue(for key: String, in config: String) -> String {
        let lines = config.components(separatedBy: .newlines)
        for line in lines where line.hasPrefix("\(key)=") {
            let value = line.replacingOccurrences(of: "\(key)=", with: "")
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return ""
    }

    private nonisolated func extractStartTime(from instanceName: String) -> Date {
        let parts = instanceName.components(separatedBy: "-")
        if let timestampPart = parts.last,
           let timestamp = TimeInterval(timestampPart) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return Date()
    }

    private nonisolated func extractBrowserName(from appPath: String) -> String {
        if appPath.contains("Google Chrome") {
            return "Google Chrome"
        } else if appPath.contains("Chromium") {
            return "Chromium"
        } else if appPath.contains("Microsoft Edge") {
            return "Microsoft Edge"
        } else if appPath.contains("Brave") {
            return "Brave Browser"
        } else if appPath.contains("Arc") {
            return "Arc"
        } else if appPath.contains("Safari") {
            return "Safari"
        }

        return "Browser"
    }

    private nonisolated func sanitizeFileNameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalarView = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalarView)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "browser" : sanitized
    }

    private nonisolated func isProcessRunning(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
