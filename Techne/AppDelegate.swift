//
//  AppDelegate.swift
//  Techne
//  应用生命周期管理
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检测启动方式，开机自启动时不显示窗口
        if wasLaunchedAsLoginItem() {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                for window in NSApp.windows where window.identifier?.rawValue == "main" {
                    window.close()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowNavigationCoordinator.shared.showMainWindow()
        return true
    }

    private func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventID == kAEOpenApplication &&
               event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
