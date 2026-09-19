import AppKit
import Testing
@testable import Techne

@MainActor
struct StatusItemControllerTests {
    @Test
    func configuredButtonUsesNativePrimaryActionAndContextMenu() throws {
        var openCount = 0
        let navigation = makeNavigationCoordinator()
        navigation.registerOpenMainWindowAction {
            openCount += 1
        }
        let controller = StatusItemController(
            mainWindowNavigation: navigation,
            terminateApplication: { }
        )
        let button = NSStatusBarButton(frame: .zero)

        controller.configure(button)

        #expect(button.menu?.items.map(\.title) == [
            SidebarItem.devEnvironment.title,
            SidebarItem.miniApp.title,
            SidebarItem.adbDeploy.title,
            "",
            AppLocalized("退出 Techne")
        ])
        #expect(button.gestureRecognizers.contains { $0 is NSClickGestureRecognizer } == false)

        _ = try #require(button.action)
        button.performClick(nil)
        #expect(openCount == 1)
    }

    @Test
    func contextMenuContainsOnlyBusinessEntriesAndQuitWithoutShortcut() throws {
        let controller = makeController()
        let menu = controller.makeMenu()

        #expect(menu.items.map(\.title) == [
            SidebarItem.devEnvironment.title,
            SidebarItem.miniApp.title,
            SidebarItem.adbDeploy.title,
            "",
            AppLocalized("退出 Techne")
        ])
        #expect(try #require(menu.items.last).keyEquivalent.isEmpty)
        #expect(menu.items.compactMap(\.image).count == 4)
    }

    @Test
    func businessMenuEntryNavigatesThroughTheSharedWindowCoordinator() throws {
        let navigation = makeNavigationCoordinator()
        let controller = StatusItemController(
            mainWindowNavigation: navigation,
            terminateApplication: { Issue.record("business navigation should not quit") }
        )
        let miniAppItem = controller.makeMenu().items[1]

        let action = try #require(miniAppItem.action)
        #expect(NSApp.sendAction(action, to: miniAppItem.target, from: miniAppItem))
        #expect(navigation.consumePendingSidebarItem() == .miniApp)
    }

    @Test
    func quitMenuEntryTerminatesThroughItsDedicatedAction() throws {
        var terminationCount = 0
        let controller = StatusItemController(
            mainWindowNavigation: makeNavigationCoordinator(),
            terminateApplication: { terminationCount += 1 }
        )
        let quitItem = try #require(controller.makeMenu().items.last)

        let action = try #require(quitItem.action)
        #expect(NSApp.sendAction(action, to: quitItem.target, from: quitItem))
        #expect(terminationCount == 1)
    }

    private func makeController() -> StatusItemController {
        StatusItemController(
            mainWindowNavigation: makeNavigationCoordinator(),
            terminateApplication: { }
        )
    }

    private func makeNavigationCoordinator() -> MainWindowNavigationCoordinator {
        MainWindowNavigationCoordinator { openWindow in
            MainWindowCoordinator(
                findWindow: { _ in nil },
                activateApp: { },
                openWindow: openWindow,
                focusWindow: { _ in }
            )
        }
    }
}
