import AppKit
import Foundation

enum BrowserLaunchError: LocalizedError {
    case launchAlreadyInProgress
    case debugPortUnavailable
    case missingTrackingDirectory
    case applicationDidNotReturnRunningInstance

    var errorDescription: String? {
        switch self {
        case .launchAlreadyInProgress:
            return "浏览器正在启动中，请勿重复点击"
        case .debugPortUnavailable:
            return "未找到可用的浏览器调试端口"
        case .missingTrackingDirectory:
            return "浏览器实例目录创建失败"
        case .applicationDidNotReturnRunningInstance:
            return "浏览器已收到启动请求，但未返回运行中的应用实例"
        }
    }
}

@MainActor
final class BrowserLaunchService {
    private static var activeLaunchKeys: Set<String> = []
    nonisolated private static let lsofExecutableCandidates = [
        "/usr/sbin/lsof",
        "/usr/bin/lsof"
    ]

    private let instanceStore: BrowserInstanceStore
    private let workspace: NSWorkspace

    init(
        instanceStore: BrowserInstanceStore = BrowserInstanceStore(),
        workspace: NSWorkspace = .shared
    ) {
        self.instanceStore = instanceStore
        self.workspace = workspace
    }

    func launchBrowser(_ request: BrowserLaunchRequest) async -> Result<Int32, Error> {
        guard reserveLaunch(for: request.launchKey) else {
            return .failure(BrowserLaunchError.launchAlreadyInProgress)
        }
        defer { releaseLaunch(for: request.launchKey) }

        var profileDirectoryURL: URL? = nil

        do {
            profileDirectoryURL = request.tracksInstance
                ? try instanceStore.makeUniqueProfileDirectory(named: request.profileDirectoryName)
                : nil
            let resolvedDebugPort = try resolveDebugPort(for: request)
            let plan = try BrowserLaunchPlan(
                request: request,
                profileDirectoryURL: profileDirectoryURL,
                resolvedDebugPort: resolvedDebugPort
            )
            let app = try await open(plan: plan)
            app.activate(options: [.activateAllWindows])

            if request.tracksInstance {
                guard let profileDirectoryURL else {
                    throw BrowserLaunchError.missingTrackingDirectory
                }

                let record = BrowserInstanceRecord(
                    instanceName: profileDirectoryURL.lastPathComponent,
                    pid: app.processIdentifier,
                    browserName: request.browser.type.rawValue,
                    browserBundleID: request.browser.type.bundleId,
                    browserAppPath: request.browser.appPath,
                    launchedURL: request.normalizedURL ?? "",
                    debugPort: resolvedDebugPort,
                    profileDirectoryPath: profileDirectoryURL.path,
                    startedAt: Date(),
                    launchTarget: request.launchTarget
                )
                try instanceStore.save(record)
            }

            NotificationCenter.default.post(name: .browserDidOpen, object: nil)
            return .success(app.processIdentifier)
        } catch {
            if let profileDirectoryURL {
                try? FileManager.default.removeItem(at: profileDirectoryURL)
            }
            return .failure(error)
        }
    }

    private func reserveLaunch(for launchKey: String) -> Bool {
        guard Self.activeLaunchKeys.contains(launchKey) == false else {
            return false
        }

        Self.activeLaunchKeys.insert(launchKey)
        return true
    }

    private func releaseLaunch(for launchKey: String) {
        Self.activeLaunchKeys.remove(launchKey)
    }

    private func resolveDebugPort(for request: BrowserLaunchRequest) throws -> Int? {
        guard request.tracksInstance else {
            return nil
        }

        let startingPort = request.requestedDebugPort ?? AppConfig.Browser.defaultDebugPort
        guard let port = findAvailablePort(startingFrom: startingPort) else {
            throw BrowserLaunchError.debugPortUnavailable
        }
        return port
    }

    private func open(plan: BrowserLaunchPlan) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = plan.activates
        configuration.createsNewApplicationInstance = plan.createsNewApplicationInstance
        configuration.arguments = plan.arguments

        return try await withCheckedThrowingContinuation { continuation in
            let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: BrowserLaunchError.applicationDidNotReturnRunningInstance)
                }
            }

            if plan.urlsToOpen.isEmpty {
                workspace.openApplication(at: plan.applicationURL, configuration: configuration, completionHandler: completion)
            } else {
                workspace.open(plan.urlsToOpen, withApplicationAt: plan.applicationURL, configuration: configuration, completionHandler: completion)
            }
        }
    }

    /// 检查端口是否可用
    /// - Parameter port: 要检查的端口号
    /// - Returns: true 表示端口可用，false 表示端口被占用，nil 表示无法确定
    /// - Note: 这是一个 nonisolated 方法，可以在后台线程安全调用
    nonisolated func isPortAvailable(_ port: Int) -> Bool? {
        guard let lsofExecutableURL = resolveLsofExecutableURL() else {
            return nil
        }

        let task = Process()
        task.executableURL = lsofExecutableURL
        task.arguments = ["-i", ":\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "BrowserLaunchService")

            if terminationStatus == 1 {
                return true
            }

            guard terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return nil
        }
    }

    private nonisolated func resolveLsofExecutableURL() -> URL? {
        let fileManager = FileManager.default

        for candidate in Self.lsofExecutableCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }

    /// 查找可用端口
    /// - Parameter startingFrom: 起始端口号
    /// - Returns: 可用的端口号，如果没有找到返回 nil
    /// - Note: 这是一个 nonisolated 方法，可以在后台线程安全调用
    nonisolated func findAvailablePort(startingFrom: Int = 9222) -> Int? {
        var port = max(0, startingFrom)

        while port < AppConfig.Browser.maxPort {
            if let available = isPortAvailable(port), available {
                return port
            }
            port += 1
        }

        return nil
    }
}
