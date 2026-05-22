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

    @Test
    @MainActor
    func showMainWindowImmediatelyOpensMissingWindowWithoutDependingOnMenuBarLifecycle() {
        var openCount = 0
        let navigation = MainWindowNavigationCoordinator(
            makeWindowCoordinator: { openWindow in
                MainWindowCoordinator(
                    findWindow: { _ in nil },
                    activateApp: { },
                    openWindow: openWindow,
                    focusWindow: { _ in }
                )
            }
        )
        navigation.registerOpenMainWindowAction {
            openCount += 1
        }

        navigation.showMainWindow()

        #expect(openCount == 1)
    }

    @Test
    @MainActor
    func lateOpenActionRegistrationDoesNotReplayEarlierReopenRequest() {
        var openCount = 0
        let navigation = MainWindowNavigationCoordinator(
            makeWindowCoordinator: { openWindow in
                MainWindowCoordinator(
                    findWindow: { _ in nil },
                    activateApp: { },
                    openWindow: openWindow,
                    focusWindow: { _ in }
                )
            }
        )

        navigation.showMainWindow()

        navigation.registerOpenMainWindowAction {
            openCount += 1
        }

        #expect(openCount == 0)
    }

    @Test
    @MainActor
    func showMainWindowSelectingSidebarStoresAtomicNavigationIntentUntilConsumed() {
        var openCount = 0
        let navigation = MainWindowNavigationCoordinator(
            makeWindowCoordinator: { openWindow in
                MainWindowCoordinator(
                    findWindow: { _ in nil },
                    activateApp: { },
                    openWindow: openWindow,
                    focusWindow: { _ in }
                )
            }
        )
        navigation.registerOpenMainWindowAction {
            openCount += 1
        }

        navigation.showMainWindow(selecting: .miniApp)

        #expect(openCount == 1)
        #expect(navigation.consumePendingSidebarItem() == .miniApp)
        #expect(navigation.consumePendingSidebarItem() == nil)
    }
}
