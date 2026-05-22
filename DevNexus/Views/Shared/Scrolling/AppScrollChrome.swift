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
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyConfiguration(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(from: nsView)
        }
    }

    private func applyConfiguration(from hostView: NSView) {
        guard let initialView = hostView.superview else {
            return
        }

        guard let scrollView = sequence(first: initialView, next: { $0.superview })
            .compactMap({ $0 as? NSScrollView })
            .first
        else {
            return
        }

        let configuration = AppScrollerPolicy.configuration(for: role)
        scrollView.scrollerStyle = configuration.scrollerStyle
        scrollView.autohidesScrollers = configuration.autohidesScrollers
        scrollView.verticalScroller?.controlSize = configuration.controlSize
        scrollView.horizontalScroller?.controlSize = configuration.controlSize
    }
}
