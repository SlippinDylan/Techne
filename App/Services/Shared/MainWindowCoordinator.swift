import AppKit

@MainActor
struct MainWindowCoordinator {
    let identifier: String
    let findWindow: (String) -> NSWindow?
    let activateApp: () -> Void
    let openWindow: () -> Void
    let focusWindow: (NSWindow) -> Void

    init(
        identifier: String = "main",
        findWindow: @escaping (String) -> NSWindow? = { id in
            NSApp.windows.first(where: { $0.identifier?.rawValue == id })
        },
        activateApp: @escaping () -> Void = {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate()
        },
        openWindow: @escaping () -> Void,
        focusWindow: @escaping (NSWindow) -> Void = { window in
            window.collectionBehavior = [.moveToActiveSpace, .managed, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    ) {
        self.identifier = identifier
        self.findWindow = findWindow
        self.activateApp = activateApp
        self.openWindow = openWindow
        self.focusWindow = focusWindow
    }

    func showMainWindow() {
        activateApp()
        if let window = findWindow(identifier) {
            focusWindow(window)
            return
        }
        openWindow()
    }
}
