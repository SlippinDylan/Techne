import AppKit

@MainActor
struct MainWindowCoordinator {
    let identifier: String
    let findWindow: (String) -> NSWindow?
    let activateApp: () -> Void
    let openWindow: () -> Void
    let focusWindow: (NSWindow) -> Void
    let closeWindow: (NSWindow) -> Void

    init(
        identifier: String = "main",
        findWindow: @escaping (String) -> NSWindow? = { id in
            NSApp.windows.first(where: { $0.identifier?.rawValue == id })
        },
        activateApp: @escaping () -> Void = {
            NSApp.activate()
        },
        openWindow: @escaping () -> Void,
        focusWindow: @escaping (NSWindow) -> Void = { window in
            window.collectionBehavior = [.moveToActiveSpace, .managed, .fullScreenAuxiliary]
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        },
        closeWindow: @escaping (NSWindow) -> Void = { $0.close() }
    ) {
        self.identifier = identifier
        self.findWindow = findWindow
        self.activateApp = activateApp
        self.openWindow = openWindow
        self.focusWindow = focusWindow
        self.closeWindow = closeWindow
    }

    func showMainWindow() {
        activateApp()
        if let window = findWindow(identifier) {
            focusWindow(window)
            return
        }
        openWindow()

        if let window = findWindow(identifier) {
            focusWindow(window)
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard let window = findWindow(identifier) else {
                return
            }
            focusWindow(window)
        }
    }

    func closeMainWindow() {
        guard let window = findWindow(identifier) else {
            return
        }
        closeWindow(window)
    }
}
