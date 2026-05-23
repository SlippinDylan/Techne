import AppKit
import SwiftUI
import Testing
@testable import DevNexus

struct ContentViewPreviewTests {
    @MainActor
    @Test
    func previewInjectsMainWindowNavigationEnvironment() {
        let hostingView = makeHostedView(rootView: ContentView.preview())

        #expect(hostingView.window != nil)
    }

    @MainActor
    private func makeHostedView<Content: View>(rootView: Content) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )

        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        return hostingView
    }
}
