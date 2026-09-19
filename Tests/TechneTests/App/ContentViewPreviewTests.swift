import AppKit
import SwiftUI
import Testing
@testable import Techne

struct ContentViewPreviewTests {
    @Test
    func sidebarGroupsKeepUtilityNavigationAtTheBottomInRequiredOrder() {
        #expect(SidebarItem.primaryItems == [.devEnvironment, .miniApp, .adbDeploy])
        #expect(SidebarItem.utilityItems == [.settings, .logs])
        #expect(SettingsPane.allCases == [.general, .about])
    }

    @MainActor
    @Test
    func previewEnvironmentRetainsInjectedNavigationCoordinator() {
        let navigationCoordinator = MainWindowNavigationCoordinator(
            makeWindowCoordinator: { _ in
                MainWindowCoordinator(
                    activateApp: {},
                    openWindow: {}
                )
            }
        )
        let environment = ContentViewPreviewEnvironment.make(
            navigationCoordinator: navigationCoordinator
        )
        #expect(environment.navigationCoordinator === navigationCoordinator)
    }

    @MainActor
    @Test
    func previewEnvironmentUsesTemporaryPersistenceAndSkipsStartupRefresh() {
        let environment = ContentViewPreviewEnvironment.make()

        #expect(environment.persistenceRoot.directoryURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(environment.projectService.projects.isEmpty)
        #expect(environment.projectService.isLoading == false)
    }

    @MainActor
    @Test
    func previewEnvironmentReleasesItsTemporaryPersistenceDirectory() {
        var environment: ContentViewPreviewEnvironment? = ContentViewPreviewEnvironment.make()
        let persistenceDirectory = try! #require(environment?.persistenceRoot.directoryURL)

        #expect(FileManager.default.fileExists(atPath: persistenceDirectory.path))

        environment = nil

        #expect(FileManager.default.fileExists(atPath: persistenceDirectory.path) == false)
    }

    @MainActor
    private func makeHostedWindow<Content: View>(rootView: Content) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )

        window.contentViewController = hostingController
        _ = window.contentViewController?.view
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        return window
    }
}
