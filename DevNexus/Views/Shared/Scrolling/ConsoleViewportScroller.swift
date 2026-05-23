import AppKit

final class ConsoleViewportScroller: NSScroller {
    private static let indicatorWidth: CGFloat = 7

    override class var isCompatibleWithOverlayScrollers: Bool {
        self == ConsoleViewportScroller.self
    }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        indicatorWidth
    }

    override func rect(for part: NSScroller.Part) -> NSRect {
        let rect = super.rect(for: part)

        switch part {
        case .knob, .knobSlot:
            return alignedIndicatorRect(from: rect)
        default:
            return rect
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knobRect = rect(for: .knob).insetBy(dx: 0.5, dy: 1)
        guard knobRect.width > 0, knobRect.height > 0 else {
            return
        }

        knobFillColor.setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobRect.width / 2,
            yRadius: min(knobRect.width / 2, knobRect.height / 2)
        ).fill()
    }

    private func alignedIndicatorRect(from rect: NSRect) -> NSRect {
        let width = min(Self.indicatorWidth, rect.width)
        let originX: CGFloat

        if userInterfaceLayoutDirection == .rightToLeft {
            originX = rect.minX
        } else {
            originX = rect.maxX - width
        }

        return NSRect(x: originX, y: rect.minY, width: width, height: rect.height)
    }

    private var knobFillColor: NSColor {
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor.white.withAlphaComponent(0.38)
        default:
            return NSColor.black.withAlphaComponent(0.32)
        }
    }
}
