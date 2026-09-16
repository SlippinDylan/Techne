import Foundation

struct BrowserInstanceRecord: Equatable, Sendable {
    let instanceName: String
    let pid: Int32
    let browserName: String
    let browserBundleID: String
    let browserAppPath: String
    let launchedURL: String
    let debugPort: Int?
    let profileDirectoryPath: String
    let startedAt: Date
    let launchTarget: BrowserLaunchTarget?

    nonisolated func makeChromeInstance() -> ChromeInstance {
        ChromeInstance(
            id: pid,
            processName: browserName,
            url: launchedURL,
            debugPort: debugPort,
            commandLine: browserAppPath,
            startTime: startedAt,
            launchTarget: launchTarget
        )
    }
}
