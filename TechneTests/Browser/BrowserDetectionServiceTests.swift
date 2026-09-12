import Foundation
import Testing
@testable import Techne

struct BrowserDetectionServiceTests {
    @Test
    func detectInstalledBrowsersSkipsMissingApplicationsReturnedByWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let chromeApp = root.appendingPathComponent("Google Chrome.app", isDirectory: true)
        try FileManager.default.createDirectory(at: chromeApp, withIntermediateDirectories: true)

        let workspace = FakeWorkspace(
            preferredURLs: [
                BrowserType.chrome.bundleId: chromeApp,
                BrowserType.brave.bundleId: root.appendingPathComponent("Brave Browser.app", isDirectory: true)
            ]
        )
        let service = BrowserDetectionService(
            workspace: workspace,
            defaultBrowserBundleIDProvider: { BrowserType.chrome.bundleId }
        )

        let browsers = service.detectInstalledBrowsers()

        #expect(browsers.map(\.type) == [.chrome])
        #expect(browsers.first?.appURL == chromeApp)
        #expect(browsers.first?.isDefault == true)
    }

    @Test
    func detectInstalledBrowsersPlacesDefaultBrowserFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let safariApp = root.appendingPathComponent("Safari.app", isDirectory: true)
        let edgeApp = root.appendingPathComponent("Microsoft Edge.app", isDirectory: true)
        try FileManager.default.createDirectory(at: safariApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: edgeApp, withIntermediateDirectories: true)

        let workspace = FakeWorkspace(
            preferredURLs: [
                BrowserType.safari.bundleId: safariApp,
                BrowserType.edge.bundleId: edgeApp
            ]
        )
        let service = BrowserDetectionService(
            workspace: workspace,
            defaultBrowserBundleIDProvider: { BrowserType.edge.bundleId }
        )

        let browsers = service.detectInstalledBrowsers()

        #expect(browsers.map(\.type) == [.edge, .safari])
        #expect(browsers.first?.isDefault == true)
    }

    @Test
    func detectInstalledBrowsersFallsBackToDiscoveredApplicationURLsAndDeduplicatesPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let arcApp = root.appendingPathComponent("Arc.app", isDirectory: true)
        try FileManager.default.createDirectory(at: arcApp, withIntermediateDirectories: true)

        let aliasURL = root.appendingPathComponent("Arc Alias.app")
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: arcApp)

        let workspace = FakeWorkspace(
            preferredURLs: [:],
            discoveredURLs: [
                BrowserType.arc.bundleId: [arcApp, aliasURL, arcApp]
            ]
        )
        let service = BrowserDetectionService(
            workspace: workspace,
            defaultBrowserBundleIDProvider: { nil }
        )

        let browsers = service.detectInstalledBrowsers()

        #expect(browsers.map(\.type) == [.arc])
        #expect(browsers.first?.appURL.resolvingSymlinksInPath() == arcApp)
    }
}

private struct FakeWorkspace: BrowserApplicationWorkspace {
    let preferredURLs: [String: URL]
    let discoveredURLs: [String: [URL]]

    init(
        preferredURLs: [String: URL],
        discoveredURLs: [String: [URL]] = [:]
    ) {
        self.preferredURLs = preferredURLs
        self.discoveredURLs = discoveredURLs
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        preferredURLs[bundleIdentifier]
    }

    func urlsForApplications(withBundleIdentifier bundleIdentifier: String) -> [URL] {
        discoveredURLs[bundleIdentifier] ?? []
    }
}
