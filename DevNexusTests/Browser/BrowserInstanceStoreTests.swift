import Darwin
import Foundation
import Testing
@testable import DevNexus

struct BrowserInstanceStoreTests {
    @Test
    func trackedInstanceRoundTripsThroughStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profileDirectory = root.appendingPathComponent("profiles/browser-1")
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let store = BrowserInstanceStore(rootDirectoryURL: root)
        let record = BrowserInstanceRecord(
            instanceName: "browser-1",
            pid: getpid(),
            browserName: "Google Chrome",
            browserBundleID: BrowserType.chrome.bundleId,
            browserAppPath: "/Applications/Google Chrome.app",
            launchedURL: "http://localhost:5173",
            debugPort: 9333,
            profileDirectoryPath: profileDirectory.path,
            startedAt: Date(timeIntervalSince1970: 1_716_000_000),
            launchTarget: BrowserLaunchTarget(
                launchSource: "project-card",
                serverPort: 5173,
                projectPath: "/Users/test/project"
            )
        )

        try store.save(record)
        let loaded = try store.loadTrackedInstances()

        #expect(loaded == [record])

        try store.removeTrackedInstance(named: record.instanceName, profileDirectoryPath: record.profileDirectoryPath)
        let reloaded = try store.loadTrackedInstances()

        #expect(reloaded.isEmpty)
    }

    @Test
    func noURLRecordStillMatchesServerViaLaunchTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profileDirectory = root.appendingPathComponent("profiles/browser-2")
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let store = BrowserInstanceStore(rootDirectoryURL: root)
        let record = BrowserInstanceRecord(
            instanceName: "browser-2",
            pid: getpid(),
            browserName: "Google Chrome",
            browserBundleID: BrowserType.chrome.bundleId,
            browserAppPath: "/Applications/Google Chrome.app",
            launchedURL: "",
            debugPort: 9333,
            profileDirectoryPath: profileDirectory.path,
            startedAt: Date(timeIntervalSince1970: 1_716_000_001),
            launchTarget: BrowserLaunchTarget(
                launchSource: "server-card",
                serverPort: 5173,
                projectPath: "/Users/test/project"
            )
        )

        try store.save(record)
        let loaded = try store.loadTrackedInstances()
        let instance = try #require(loaded.first?.makeChromeInstance())
        let server = DevServer(
            id: 111,
            processName: "node",
            port: 5173,
            projectPath: "/Users/test/project",
            projectName: "project",
            serverType: .vite,
            commandLine: "node"
        )

        #expect(instance.isRelated(to: server))
    }

    @Test
    func legacyURLOnlyRecordStillMatchesServer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profileDirectory = root.appendingPathComponent("profiles/browser-3")
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let instanceName = "browser-3"
        try """
        INSTANCE_NAME="browser-3"
        INSTANCE_BROWSER_NAME="Google Chrome"
        INSTANCE_BROWSER_BUNDLE_ID="\(BrowserType.chrome.bundleId)"
        INSTANCE_BROWSER_APP_PATH="/Applications/Google Chrome.app"
        INSTANCE_URL="http://localhost:4173"
        INSTANCE_DEBUG_PORT="9333"
        INSTANCE_PROFILE_DIR="\(profileDirectory.path)"
        INSTANCE_STARTED_AT="2026-05-21T00:00:00Z"
        """.write(
            to: root.appendingPathComponent("\(instanceName).config"),
            atomically: true,
            encoding: .utf8
        )
        try "\(getpid())".write(
            to: root.appendingPathComponent("\(instanceName).pid"),
            atomically: true,
            encoding: .utf8
        )

        let store = BrowserInstanceStore(rootDirectoryURL: root)
        let loaded = try store.loadTrackedInstances()
        let instance = try #require(loaded.first?.makeChromeInstance())
        let server = DevServer(
            id: 222,
            processName: "node",
            port: 4173,
            projectPath: "/Users/other/project",
            projectName: "legacy",
            serverType: .vite,
            commandLine: "node"
        )

        #expect(instance.isRelated(to: server))
    }

    @Test
    func loadTrackedInstancesSkipsCorruptedActiveRecordAndKeepsHealthyOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let healthyProfile = root.appendingPathComponent("profiles/healthy")
        try FileManager.default.createDirectory(at: healthyProfile, withIntermediateDirectories: true)

        let store = BrowserInstanceStore(rootDirectoryURL: root)
        let healthyRecord = BrowserInstanceRecord(
            instanceName: "healthy",
            pid: getpid(),
            browserName: "Google Chrome",
            browserBundleID: BrowserType.chrome.bundleId,
            browserAppPath: "/Applications/Google Chrome.app",
            launchedURL: "http://localhost:3000",
            debugPort: 9222,
            profileDirectoryPath: healthyProfile.path,
            startedAt: Date(timeIntervalSince1970: 1_716_000_002),
            launchTarget: BrowserLaunchTarget(
                launchSource: "project-card",
                serverPort: 3000,
                projectPath: "/Users/test/project"
            )
        )
        try store.save(healthyRecord)

        try "\(getpid())".write(
            to: root.appendingPathComponent("missing-config.pid"),
            atomically: true,
            encoding: .utf8
        )
        try """
        INSTANCE_NAME="broken"
        INSTANCE_URL="http://localhost:9999"
        """.write(
            to: root.appendingPathComponent("broken-config.config"),
            atomically: true,
            encoding: .utf8
        )
        try "\(getpid())".write(
            to: root.appendingPathComponent("broken-config.pid"),
            atomically: true,
            encoding: .utf8
        )

        let loaded = try store.loadTrackedInstances()

        #expect(loaded == [healthyRecord])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing-config.pid").path) == false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("broken-config.pid").path) == false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("broken-config.config").path) == false)
    }
}
