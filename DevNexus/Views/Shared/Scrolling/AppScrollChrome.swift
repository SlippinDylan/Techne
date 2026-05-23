import AppKit
import SwiftUI

struct AppScrollChrome: ViewModifier {
    let role: AppScrollSurfaceRole

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.automatic)
            .background(AppScrollViewConfigurator(role: role))
    }
}

extension View {
    func appScrollChrome(_ role: AppScrollSurfaceRole) -> some View {
        modifier(AppScrollChrome(role: role))
    }
}

private struct AppScrollViewConfigurator: NSViewRepresentable {
    let role: AppScrollSurfaceRole

    func makeNSView(context: Context) -> NSView {
        let view = AppScrollConfigurationHostView()
        view.applyConfiguration = applyConfiguration(from:)
        applyConfiguration(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let hostView = nsView as? AppScrollConfigurationHostView {
            hostView.applyConfiguration = applyConfiguration(from:)
        }
        applyConfiguration(from: nsView)
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else {
                return
            }

            applyConfiguration(from: nsView)
        }
    }

    private func applyConfiguration(from hostView: NSView) {
        guard let scrollView = resolvedScrollView(from: hostView) else {
            return
        }

        let configuration = AppScrollerPolicy.configuration(for: role)
        scrollView.scrollerStyle = configuration.scrollerStyle
        scrollView.autohidesScrollers = configuration.autohidesScrollers
        scrollView.scrollerKnobStyle = .default
        scrollView.verticalScroller?.controlSize = configuration.controlSize
        scrollView.horizontalScroller?.controlSize = configuration.controlSize
        scrollView.tile()
    }

    private func resolvedScrollView(from hostView: NSView) -> NSScrollView? {
        if let scrollView = hostView.enclosingScrollView {
            return scrollView
        }

        for candidate in sequence(first: hostView, next: { $0.superview }) {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }

            if let scrollView = firstDescendantScrollView(in: candidate) {
                return scrollView
            }
        }

        return nil
    }

    private func firstDescendantScrollView(in rootView: NSView) -> NSScrollView? {
        for subview in rootView.subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }

            if let scrollView = firstDescendantScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }
}

private final class AppScrollConfigurationHostView: NSView {
    var applyConfiguration: ((NSView) -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyConfiguration?(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration?(self)
    }

    override func layout() {
        super.layout()
        applyConfiguration?(self)
    }
}
