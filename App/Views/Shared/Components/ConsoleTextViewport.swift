import AppKit
import SwiftUI

struct ConsoleTextViewport: NSViewRepresentable {
    private static let autoFollowTolerance: CGFloat = 24

    let text: String
    let isPlaceholder: Bool
    let padding: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeScrollView()
        let textView = makeTextView(padding: padding)
        context.coordinator.textView = textView
        scrollView.documentView = textView
        updateTextView(textView, using: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView ?? scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.textView = textView
        context.coordinator.lastKnownWidth = max(scrollView.contentSize.width, 1)
        let previousViewportState = viewportState(for: scrollView)
        let previousText = textView.string
        updateTextView(textView, using: context)
        textView.layoutSubtreeIfNeeded()

        if previousText != text {
            let updatedViewportState = viewportState(for: scrollView)
            if previousViewportState.shouldFollowOutput {
                scrollToBottom(in: scrollView, viewportState: updatedViewportState)
            } else {
                restoreViewport(
                    to: previousViewportState.originY,
                    in: scrollView,
                    viewportState: updatedViewportState
                )
            }
        }
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller?.controlSize = .small
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        return scrollView
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

    private func scrollToBottom(in scrollView: NSScrollView, viewportState: ViewportState) {
        let bottomPoint = NSPoint(x: 0, y: viewportState.maxLegalOriginY)
        scrollView.contentView.scroll(to: bottomPoint)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func restoreViewport(
        to previousOriginY: CGFloat,
        in scrollView: NSScrollView,
        viewportState: ViewportState
    ) {
        let clampedOriginY = min(max(previousOriginY, 0), viewportState.maxLegalOriginY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedOriginY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateDocumentFrame(for textView: NSTextView, proposedWidth: CGFloat, padding: CGFloat) {
        let width = max(proposedWidth, 1)
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            textView.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            return
        }

        textContainer.containerSize = NSSize(
            width: max(width - (padding * 2), 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)

        let textHeight = layoutManager.usedRect(for: textContainer).height
        let totalHeight = ceil(textHeight + (padding * 2))
        textView.frame = NSRect(x: 0, y: 0, width: width, height: max(totalHeight, 1))
    }

    private func viewportState(for scrollView: NSScrollView) -> ViewportState {
        let viewportHeight = max(scrollView.contentSize.height, 0)
        let documentHeight = max(scrollView.documentView?.frame.height ?? 0, 0)
        let maxLegalOriginY = max(documentHeight - viewportHeight, 0)
        let originY = min(max(scrollView.contentView.bounds.origin.y, 0), maxLegalOriginY)

        return ViewportState(
            originY: originY,
            maxLegalOriginY: maxLegalOriginY,
            shouldFollowOutput: (maxLegalOriginY - originY) <= Self.autoFollowTolerance
        )
    }

    private struct ViewportState {
        let originY: CGFloat
        let maxLegalOriginY: CGFloat
        let shouldFollowOutput: Bool
    }

    final class Coordinator {
        fileprivate var textView: NSTextView?
        fileprivate var lastKnownWidth: CGFloat = 1
    }
}
