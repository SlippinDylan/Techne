import Observation

@Observable
@MainActor
final class MainWindowNavigationCoordinator {
    static let shared = MainWindowNavigationCoordinator()

    private let makeWindowCoordinator: (@escaping () -> Void) -> MainWindowCoordinator
    private var openMainWindowAction: (() -> Void)?

    private(set) var pendingSidebarItem: SidebarItem?
    private(set) var selectionRevision = 0

    init(
        makeWindowCoordinator: @escaping (@escaping () -> Void) -> MainWindowCoordinator = { openWindow in
            MainWindowCoordinator(openWindow: openWindow)
        }
    ) {
        self.makeWindowCoordinator = makeWindowCoordinator
    }

    func registerOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    func showMainWindow(selecting sidebarItem: SidebarItem? = nil) {
        if let sidebarItem {
            pendingSidebarItem = sidebarItem
            selectionRevision &+= 1
        }

        let openMainWindowAction = openMainWindowAction ?? { }
        makeWindowCoordinator(openMainWindowAction).showMainWindow()
    }

    func closeMainWindow() {
        makeWindowCoordinator(openMainWindowAction ?? { }).closeMainWindow()
    }

    func consumePendingSidebarItem() -> SidebarItem? {
        defer { pendingSidebarItem = nil }
        return pendingSidebarItem
    }
}
