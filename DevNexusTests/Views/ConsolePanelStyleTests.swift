import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import DevNexus

@Suite(.serialized)
struct ConsolePanelStyleTests {
    @Test
    func embeddedTerminalUsesExpectedConfiguration() {
        let configuration = ConsolePanelStyle.configuration(for: .embeddedTerminal)

        #expect(
            configuration == ConsolePanelStyle.Configuration(
                shell: .init(
                    outerCornerRadius: 0,
                    contentPadding: 0,
                    headerSpacing: AppConfig.UI.mediumSpacing,
                    showsHeaderDivider: true
                ),
                viewport: .init(
                    cornerRadius: AppConfig.UI.mediumCornerRadius,
                    padding: AppConfig.UI.mediumPadding,
                    sizing: .fixed(ConsolePanelStyle.embeddedTerminalViewportHeight)
                ),
                palette: ConsolePanelStyle.sharedPalette
            )
        )
    }

    @Test
    func logWindowUsesExpectedConfiguration() {
        let configuration = ConsolePanelStyle.configuration(for: .logWindow)

        #expect(
            configuration == ConsolePanelStyle.Configuration(
                shell: .init(
                    outerCornerRadius: AppConfig.UI.largeCornerRadius,
                    contentPadding: AppConfig.UI.mediumPadding,
                    headerSpacing: AppConfig.UI.largeSpacing,
                    showsHeaderDivider: false
                ),
                viewport: .init(
                    cornerRadius: AppConfig.UI.mediumCornerRadius,
                    padding: AppConfig.UI.mediumPadding,
                    sizing: .flexible
                ),
                palette: ConsolePanelStyle.sharedPalette
            )
        )
    }

    @Test
    func logWindowConfigurationKeepsFlexibleViewportAndNoHeaderDivider() {
        let configuration = ConsolePanelStyle.configuration(for: .logWindow)

        #expect(configuration.shell.showsHeaderDivider == false)

        switch configuration.viewport.sizing {
        case .flexible:
            break
        case .fixed:
            Issue.record("Log window panels must remain flexible and avoid fixed viewport sizing.")
        }
    }

    @Test
    func logWindowShellIsRoomierWhilePaletteStaysShared() {
        let embedded = ConsolePanelStyle.configuration(for: .embeddedTerminal)
        let logWindow = ConsolePanelStyle.configuration(for: .logWindow)

        #expect(logWindow.shell.outerCornerRadius > embedded.shell.outerCornerRadius)
        #expect(logWindow.shell.headerSpacing > embedded.shell.headerSpacing)
        #expect(logWindow.palette == embedded.palette)
    }

    @Test
    func embeddedTerminalToolbarPanelsKeepHeaderDividerAndFixedViewportSizing() {
        let configuration = ConsolePanelStyle.configuration(for: .embeddedTerminal)
        let container = ConsolePanelContainer(configuration: configuration) {
            Text("Toolbar")
        } content: {
            Text("Output")
        }

        #expect(configuration.shell.showsHeaderDivider)

        switch configuration.viewport.sizing {
        case .fixed(let height):
            #expect(height == ConsolePanelStyle.embeddedTerminalViewportHeight)
        case .flexible:
            Issue.record("Embedded terminal toolbar panels must keep a fixed viewport height.")
        }

        _ = container
    }

    @MainActor
    @Test
    func embeddedConsoleSectionUsesSharedCompactPaddingAroundViewport() {
        let hostedView = makeHostedView(
            rootView: EmbeddedConsoleSection(
                output: "Output line",
                emptyText: "Empty"
            )
            .frame(width: 480)
        )

        let expectedHeight = ConsolePanelStyle.embeddedTerminalViewportHeight + (EmbeddedConsoleSection.outerPadding * 2)
        let measuredHeight = hostedView.fittingSize.height

        #expect(abs(measuredHeight - expectedHeight) <= 2)
    }

    @MainActor
    @Test
    func embeddedConsoleSectionAllowsZeroOuterPaddingForFlushCardLayouts() {
        let hostedView = makeHostedView(
            rootView: EmbeddedConsoleSection(
                output: "Output line",
                emptyText: "Empty",
                outerPadding: 0
            )
            .frame(width: 480)
        )

        let expectedHeight = ConsolePanelStyle.embeddedTerminalViewportHeight
        let measuredHeight = hostedView.fittingSize.height

        #expect(abs(measuredHeight - expectedHeight) <= 2)
    }

    @MainActor
    @Test
    func terminalPanelWithoutToolbarDoesNotReserveHeaderChromeHeight() {
        let configuration = ConsolePanelStyle.configuration(for: .embeddedTerminal)
        let hostedView = makeHostedView(
            rootView: TerminalPanel(
                output: "Output line",
                emptyText: "Empty",
                configuration: configuration
            )
            .frame(width: 480)
        )

        let expectedHeight = ConsolePanelStyle.embeddedTerminalViewportHeight
        let measuredHeight = hostedView.fittingSize.height

        #expect(abs(measuredHeight - expectedHeight) <= 2)
    }

    @Test
    func logViewReconcilesSelectionToVisibleFilteredLogs() {
        let retainedLog = LogEntry(level: .info, message: "Visible")
        let filteredOutLog = LogEntry(level: .error, message: "Filtered")
        let currentSelection: Set<UUID> = [retainedLog.id, filteredOutLog.id]

        let reconciledSelection = LogView.reconciledSelection(
            currentSelection,
            visibleLogs: [retainedLog]
        )

        #expect(reconciledSelection == [retainedLog.id])
    }

    @MainActor
    @Test
    func logViewWithEntriesRendersStructuredListBackedByAppKitTable() {
        let logService = makeTestLogService(logs: [
            LogEntry(level: .info, message: "Structured row", category: "ConsolePanelStyleTests")
        ])

        let hostedView = makeHostedLogView(logService: logService)

        #expect(hostedView.containsDescendant(ofType: NSTableView.self))
    }

    @MainActor
    @Test
    func consoleViewportScrollViewAppliesUnifiedConsoleScrollerChrome() {
        let scrollView = ConsoleViewportScrollView()

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.verticalScroller is ConsoleViewportScroller)
        #expect(scrollView.verticalScroller?.controlSize == .regular)
    }

    @MainActor
    @Test
    func emptyLogViewWithoutEntriesDoesNotRenderStructuredTable() {
        let logService = makeTestLogService(logs: [])

        let hostedView = makeHostedLogView(logService: logService)

        #expect(hostedView.containsDescendant(ofType: NSTableView.self) == false)
    }

    @MainActor
    @Test
    func logViewRenderedChromeIncludesLogWindowShellAndViewportCornerRadii() {
        let configuration = ConsolePanelStyle.configuration(for: .logWindow)
        let logService = makeTestLogService(logs: [
            LogEntry(level: .success, message: "Corner radius smoke test", category: "ConsolePanelStyleTests")
        ])

        let hostedView = makeHostedLogView(logService: logService)
        let cornerRadii = hostedView.allDescendantCornerRadii()

        #expect(cornerRadii.containsApproximately(configuration.shell.outerCornerRadius))
        #expect(cornerRadii.containsApproximately(configuration.viewport.cornerRadius))
    }

    @MainActor
    @Test
    func terminalPanelScrollViewUsesOverlayAutohidingRegularScrollerChrome() {
        let hostedView = makeHostedView(
            rootView: TerminalPanel(
                output: Array(repeating: "Output line", count: 80).joined(separator: "\n"),
                emptyText: "Empty"
            )
            .frame(width: 480, height: 260),
            frame: NSRect(x: 0, y: 0, width: 480, height: 260)
        )

        guard let scrollView = hostedView.firstDescendantScrollView() else {
            Issue.record("Expected terminal panel to host an NSScrollView.")
            return
        }

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.verticalScroller?.controlSize == .regular)
    }

    @MainActor
    @Test
    func terminalPanelUsesExplicitConsoleViewportScrollViewHost() {
        let hostedView = makeHostedView(
            rootView: TerminalPanel(
                output: Array(repeating: "Output line", count: 80).joined(separator: "\n"),
                emptyText: "Empty"
            )
            .frame(width: 480, height: 260),
            frame: NSRect(x: 0, y: 0, width: 480, height: 260)
        )

        guard let scrollView = hostedView.firstDescendantScrollView() else {
            Issue.record("Expected terminal panel to host an NSScrollView.")
            return
        }

        #expect(String(describing: type(of: scrollView)) == "ConsoleViewportScrollView")
        #expect(scrollView.containsDescendant(ofType: NSTextView.self))
    }

    @MainActor
    @Test
    func terminalPanelKeepsViewportWithinDocumentBoundsAfterLiveOutputUpdate() {
        let model = ConsoleOutputModel(output: "Booting...")
        let hostedView = makeHostedView(
            rootView: StatefulTerminalPanel(model: model)
                .frame(width: 480, height: 260),
            frame: NSRect(x: 0, y: 0, width: 480, height: 260)
        )

        guard let scrollView = hostedView.firstDescendantScrollView(),
              let documentView = scrollView.documentView else {
            Issue.record("Expected terminal panel to host an NSScrollView with a document view.")
            return
        }

        model.output = (0..<120).map { "line \($0)" }.joined(separator: "\n")
        flushHostedView(hostedView)

        let clipOriginY = scrollView.contentView.bounds.origin.y
        let maxLegalOriginY = max(documentView.frame.height - scrollView.contentSize.height, 0)

        #expect(clipOriginY <= maxLegalOriginY + 0.5)
    }

    @MainActor
    @Test
    func terminalPanelPreservesReaderPositionWhenUserScrolledAwayFromBottom() {
        let model = ConsoleOutputModel(
            output: (0..<120).map { "line \($0)" }.joined(separator: "\n")
        )
        let hostedView = makeHostedView(
            rootView: StatefulTerminalPanel(model: model)
                .frame(width: 480, height: 260),
            frame: NSRect(x: 0, y: 0, width: 480, height: 260)
        )

        guard let scrollView = hostedView.firstDescendantScrollView() else {
            Issue.record("Expected terminal panel to host an NSScrollView.")
            return
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        flushHostedView(hostedView)

        let preservedOriginY = scrollView.contentView.bounds.origin.y
        model.output += "\nnew line after manual scroll"
        flushHostedView(hostedView)

        #expect(abs(scrollView.contentView.bounds.origin.y - preservedOriginY) <= 0.5)
    }

    @MainActor
    @Test
    func logViewStructuredListUsesOverlayAutohidingRegularScrollerChrome() {
        let logService = makeTestLogService(logs: (0..<40).map { index in
            LogEntry(level: .info, message: "Structured row \(index)", category: "ConsolePanelStyleTests")
        })

        let hostedView = makeHostedLogView(logService: logService)

        guard let scrollView = hostedView.firstDescendantScrollView(containing: NSTableView.self) else {
            Issue.record("Expected structured log list to host an NSScrollView backed by NSTableView.")
            return
        }

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.verticalScroller?.controlSize == .regular)
    }

    @MainActor
    @Test
    func logViewStructuredListUsesExplicitConsoleViewportScrollViewHost() {
        let logService = makeTestLogService(logs: (0..<40).map { index in
            LogEntry(level: .info, message: "Structured row \(index)", category: "ConsolePanelStyleTests")
        })

        let hostedView = makeHostedLogView(logService: logService)

        guard let scrollView = hostedView.firstDescendantScrollView(containing: NSTableView.self) else {
            Issue.record("Expected structured log list to host an NSScrollView backed by NSTableView.")
            return
        }

        #expect(String(describing: type(of: scrollView)) == "ConsoleViewportScrollView")
    }

    @MainActor
    private func makeHostedLogView(logService: LogService) -> NSView {
        makeHostedView(
            rootView: LogView()
                .environment(logService)
                .frame(width: 900, height: 700),
            frame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )
    }

    @MainActor
    private func makeHostedView<Content: View>(
        rootView: Content,
        frame: NSRect = NSRect(x: 0, y: 0, width: 900, height: 700)
    ) -> NSHostingView<Content> {
        let hostingView = RetainedHostingView(
            rootView: rootView
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )

        window.contentView = hostingView
        hostingView.retainedWindow = window
        hostingView.frame = window.contentView?.bounds ?? frame
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        return hostingView
    }

    @MainActor
    private func makeTestLogService(logs: [LogEntry]) -> LogService {
        LogService(initialLogs: logs)
    }

    @MainActor
    private func flushHostedView(_ hostedView: NSView) {
        hostedView.layoutSubtreeIfNeeded()
        hostedView.window?.layoutIfNeeded()
        hostedView.window?.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hostedView.layoutSubtreeIfNeeded()
    }
}

private final class RetainedHostingView<Content: View>: NSHostingView<Content> {
    var retainedWindow: NSWindow?
}

private final class ConsoleOutputModel: ObservableObject {
    @Published var output: String

    init(output: String) {
        self.output = output
    }
}

private struct StatefulTerminalPanel: View {
    @ObservedObject var model: ConsoleOutputModel

    var body: some View {
        TerminalPanel(
            output: model.output,
            emptyText: "Empty"
        )
    }
}

private extension NSView {
    func firstDescendantScrollView() -> NSScrollView? {
        if let scrollView = self as? NSScrollView {
            return scrollView
        }

        return subviews.lazy.compactMap { $0.firstDescendantScrollView() }.first
    }

    func containsDescendant<T: NSView>(ofType type: T.Type) -> Bool {
        if self is T {
            return true
        }

        return subviews.contains { $0.containsDescendant(ofType: type) }
    }

    func allDescendantCornerRadii() -> [CGFloat] {
        let currentRadius = layer.map { $0.cornerRadius > 0 ? [$0.cornerRadius] : [] } ?? []
        return currentRadius + subviews.flatMap { $0.allDescendantCornerRadii() }
    }

    func firstDescendantScrollView<T: NSView>(containing type: T.Type) -> NSScrollView? {
        if let scrollView = self as? NSScrollView, scrollView.documentView?.containsDescendant(ofType: type) == true {
            return scrollView
        }

        return subviews.lazy.compactMap { $0.firstDescendantScrollView(containing: type) }.first
    }

    func frame(in ancestor: NSView) -> NSRect? {
        guard isDescendant(of: ancestor) || self === ancestor else {
            return nil
        }

        return convert(bounds, to: ancestor)
    }
}

private extension Array where Element == CGFloat {
    func containsApproximately(_ value: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
        contains { abs($0 - value) <= tolerance }
    }
}
