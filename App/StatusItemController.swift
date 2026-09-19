import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusBar: NSStatusBar
    private let mainWindowNavigation: MainWindowNavigationCoordinator
    private let terminateApplication: () -> Void
    private(set) var statusItem: NSStatusItem?

    init(
        statusBar: NSStatusBar = .system,
        mainWindowNavigation: MainWindowNavigationCoordinator = .shared,
        terminateApplication: @escaping () -> Void = { NSApp.terminate(nil) }
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

        let image = NSImage(
            systemSymbolName: "macbook.and.iphone",
            accessibilityDescription: "Techne"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Techne"

        let primaryClick = NSClickGestureRecognizer(target: self, action: #selector(handlePrimaryClick))
        primaryClick.buttonMask = 0x1
        button.addGestureRecognizer(primaryClick)

        let secondaryClick = NSClickGestureRecognizer(target: self, action: #selector(handleSecondaryClick))
        secondaryClick.buttonMask = 0x2
        button.addGestureRecognizer(secondaryClick)

        statusItem = item
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

    @objc
    private func handlePrimaryClick() {
        mainWindowNavigation.showMainWindow()
    }

    @objc
    private func handleSecondaryClick(_ recognizer: NSClickGestureRecognizer) {
        guard let button = recognizer.view as? NSStatusBarButton else {
            return
        }

        button.highlight(true)
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        button.highlight(false)
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
