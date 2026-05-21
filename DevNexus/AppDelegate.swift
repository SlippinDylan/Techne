//
//  AppDelegate.swift
//  DevNexus
//
//  应用生命周期管理 - 处理 Cmd+Q 长按退出和窗口行为
//

import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: Any?
    private weak var activeToastView: NSView?

    // Cmd+Q 退出相关
    private var quitTimerTask: Task<Void, Never>?
    private var lastQuitKeyTime: Date? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupQuitBehavior()

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

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    // MARK: - Private Methods

    private func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        quitTimerTask?.cancel()
        quitTimerTask = nil
    }

    deinit {
        MainActor.assumeIsolated {
            cleanup()
        }
    }

    // MARK: - Quit Behavior

    private func setupQuitBehavior() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                if !event.isARepeat {
                    self.handleQuitAttempt()
                }
                return nil
            }
            return event
        }
    }

    private func handleQuitAttempt() {
        let now = Date()
        
        if let lastTime = lastQuitKeyTime, now.timeIntervalSince(lastTime) < 2.0 {
            // 双击确认，直接退出
            NSApp.terminate(nil)
        } else {
            // 第一次按下
            lastQuitKeyTime = now
            showQuitHint()
            
            quitTimerTask?.cancel()
            quitTimerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }
                
                self?.lastQuitKeyTime = nil
                self?.hideQuitHint()
            }
        }
    }

    private func showQuitHint() {
        let hint = "再按一次 Cmd+Q 退出 DevNexus"
        showFloatingQuitHint(with: hint)
    }

    private func hideQuitHint() {
        for window in NSApp.windows {
            if window is NSPanel && window.level == .floating && window.styleMask.contains(.borderless) {
                window.close()
            }
        }
        activeToastView = nil
    }

    private func showFloatingQuitHint(with hint: String) {
        let toastView = createToastView(with: hint)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = toastView

        let targetFrame = preferredQuitHintTargetFrame()
        let windowFrame = window.frame
        let x = targetFrame.midX - windowFrame.width / 2
        let y = targetFrame.midY - windowFrame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                window.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    window.close()
                }
            })
        }
    }

    private func preferredQuitHintTargetFrame() -> NSRect {
        if let keyWindow = NSApp.keyWindow {
            return keyWindow.frame
        }

        if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            return mainWindow.frame
        }

        if let screen = NSScreen.main {
            return screen.visibleFrame
        }

        return NSRect(x: 0, y: 0, width: 280, height: 56)
    }

    private func createToastView(with hint: String) -> NSView {
        let toastView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        self.activeToastView = toastView
        toastView.wantsLayer = true
        toastView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        toastView.layer?.cornerRadius = 12
        toastView.layer?.shadowColor = NSColor.black.cgColor
        toastView.layer?.shadowOpacity = 0.25
        toastView.layer?.shadowOffset = CGSize(width: 0, height: 2)
        toastView.layer?.shadowRadius = 10

        let label = NSTextField(labelWithString: hint)
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: (toastView.bounds.width - label.bounds.width) / 2,
            y: (toastView.bounds.height - label.bounds.height) / 2
        )
        toastView.addSubview(label)

        return toastView
    }

    private func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventID == kAEOpenApplication &&
               event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let switchToDevEnvironment = Notification.Name("switchToDevEnvironment")
    static let switchToMiniApp = Notification.Name("switchToMiniApp")
    static let switchToLog = Notification.Name("switchToLog")
    static let switchToAbout = Notification.Name("switchToAbout")
    static let addDevProject = Notification.Name("addDevProject")
    static let addMiniAppProject = Notification.Name("addMiniAppProject")
    static let switchToADBDeploy = Notification.Name("switchToADBDeploy")
    static let switchToSettings = Notification.Name("switchToSettings")
}
