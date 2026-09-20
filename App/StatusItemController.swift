import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusBar: NSStatusBar
    private let mainWindowNavigation: MainWindowNavigationCoordinator
    private let terminateApplication: () -> Void
    private lazy var menu = makeMenu()
    private(set) var statusItem: NSStatusItem?

    init(
        statusBar: NSStatusBar = .system,
        mainWindowNavigation: MainWindowNavigationCoordinator = .shared,
        terminateApplication: @escaping () -> Void = { ApplicationQuitCoordinator.shared.requestQuit() }
    ) {
        self.statusBar = statusBar
        self.mainWindowNavigation = mainWindowNavigation
        self.terminateApplication = terminateApplication
        super.init()
    }

    func start() {
        guard statusItem == nil else {
            return
        }

        let item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            statusBar.removeStatusItem(item)
            return
        }

        configure(button)
        statusItem = item
    }

    func configure(_ button: NSStatusBarButton) {
        let image = NSImage(
            systemSymbolName: "macbook.and.iphone",
            accessibilityDescription: "Techne"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Techne"
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        for item in SidebarItem.primaryItems {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(openSidebarItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.rawValue
            menuItem.image = menuImage(symbolName: item.icon, description: item.title)
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let quitTitle = AppLocalized("退出 Techne")
        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(quitApplication(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.image = menuImage(symbolName: "power", description: quitTitle)
        menu.addItem(quitItem)

        return menu
    }

    static func isContextMenuEvent(_ eventType: NSEvent.EventType?) -> Bool {
        eventType == .rightMouseUp
    }

    @objc
    private func handleStatusItemClick() {
        if Self.isContextMenuEvent(NSApp.currentEvent?.type) {
            showContextMenu()
        } else {
            mainWindowNavigation.showMainWindow()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else {
            return
        }

        statusItem?.menu = menu
        defer { statusItem?.menu = nil }
        button.performClick(nil)
    }

    @objc
    private func openSidebarItem(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let item = SidebarItem(rawValue: rawValue)
        else {
            return
        }

        mainWindowNavigation.showMainWindow(selecting: item)
    }

    @objc
    private func quitApplication(_ sender: NSMenuItem) {
        terminateApplication()
    }

    private func menuImage(symbolName: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
