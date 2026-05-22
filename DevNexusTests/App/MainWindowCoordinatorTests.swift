import AppKit
import Testing
@testable import DevNexus

struct MainWindowCoordinatorTests {
    @Test
    @MainActor
    func reusesExistingMainWindowWithoutRequestingAnotherOpen() {
        let existingWindow = NSWindow()
        existingWindow.identifier = NSUserInterfaceItemIdentifier("main")

        let coordinator = MainWindowCoordinator(
            findWindow: { _ in existingWindow },
            activateApp: { },
            openWindow: { Issue.record("openWindow should not be called") },
            focusWindow: { window in
                #expect(window === existingWindow)
            }
        )

        coordinator.showMainWindow()
    }

    @Test
    @MainActor
    func opensMainWindowWhenNoExistingWindowIsAvailable() {
        var openCount = 0

        let coordinator = MainWindowCoordinator(
            findWindow: { _ in nil },
            activateApp: { },
            openWindow: { openCount += 1 },
            focusWindow: { _ in }
        )

        coordinator.showMainWindow()

        #expect(openCount == 1)
    }
}
