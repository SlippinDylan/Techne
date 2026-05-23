import AppKit

final class ConsoleViewportScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func tile() {
        super.tile()
        applyScrollerConfiguration()
    }

    private func configure() {
        drawsBackground = false
        backgroundColor = .clear
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
        contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        automaticallyAdjustsContentInsets = false
        scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        applyScrollerConfiguration()
    }

    private func applyScrollerConfiguration() {
        let configuration = AppScrollerPolicy.configuration(for: .consoleViewport)
        installVerticalScrollerIfNeeded()
        scrollerStyle = configuration.scrollerStyle
        autohidesScrollers = configuration.autohidesScrollers
        scrollerKnobStyle = .default
        verticalScroller?.controlSize = configuration.controlSize
        horizontalScroller?.controlSize = configuration.controlSize
    }

    private func installVerticalScrollerIfNeeded() {
        guard !(verticalScroller is ConsoleViewportScroller) else {
            return
        }

        let scroller = ConsoleViewportScroller(frame: .zero)
        scroller.controlSize = AppScrollerPolicy.configuration(for: .consoleViewport).controlSize
        scroller.knobStyle = .default
        verticalScroller = scroller
    }
}
