import AppKit
import SwiftUI

struct ConsoleTextViewport: NSViewRepresentable {
    let text: String
    let isPlaceholder: Bool
    let padding: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ConsoleViewportScrollView {
        let scrollView = ConsoleViewportScrollView()
        let textView = makeTextView(padding: padding)
        context.coordinator.textView = textView
        scrollView.documentView = textView
        updateTextView(textView, using: context)
        return scrollView
    }

    func updateNSView(_ scrollView: ConsoleViewportScrollView, context: Context) {
        guard let textView = context.coordinator.textView ?? scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.textView = textView
        context.coordinator.lastKnownWidth = max(scrollView.contentSize.width, 1)
        let previousText = textView.string
        updateTextView(textView, using: context)
        textView.layoutSubtreeIfNeeded()

        if previousText != text {
            scrollToBottom(in: scrollView)
        }
    }

    private func makeTextView(padding: CGFloat) -> NSTextView {
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainerInset = NSSize(width: padding, height: padding)
        textView.allowsUndo = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    private func updateTextView(_ textView: NSTextView, using context: Context) {
        let textColor = isPlaceholder
            ? NSColor.secondaryLabelColor
            : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: AppConfig.UI.smallFontSize, weight: .regular),
            .foregroundColor: textColor
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)

        textView.textStorage?.setAttributedString(attributedString)
        textView.insertionPointColor = .clear
        updateDocumentFrame(
            for: textView,
            proposedWidth: context.coordinator.lastKnownWidth,
            padding: padding
        )
    }

    private func scrollToBottom(in scrollView: NSScrollView) {
        let bottomPoint = NSPoint(x: 0, y: max(scrollView.documentView?.frame.height ?? 0, 0))
        scrollView.contentView.scroll(to: bottomPoint)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateDocumentFrame(for textView: NSTextView, proposedWidth: CGFloat, padding: CGFloat) {
        let width = max(proposedWidth, 1)
        let textHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        let totalHeight = ceil(textHeight + (padding * 2))
        textView.frame = NSRect(x: 0, y: 0, width: width, height: max(totalHeight, 1))
    }

    final class Coordinator {
        fileprivate var textView: NSTextView?
        fileprivate var lastKnownWidth: CGFloat = 1
    }
}
