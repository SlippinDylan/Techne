import AppKit

enum AppScrollSurfaceRole {
    case mainContent
    case utilityPanel
}

struct AppScrollerConfiguration: Equatable {
    let scrollerStyle: NSScroller.Style
    let autohidesScrollers: Bool
    let controlSize: NSControl.ControlSize
}

enum AppScrollerPolicy {
    static func configuration(
        for role: AppScrollSurfaceRole,
        preferredStyle: NSScroller.Style = NSScroller.preferredScrollerStyle
    ) -> AppScrollerConfiguration {
        switch (role, preferredStyle) {
        case (.mainContent, .legacy):
            AppScrollerConfiguration(
                scrollerStyle: .legacy,
                autohidesScrollers: false,
                controlSize: .regular
            )
        case (.mainContent, .overlay):
            AppScrollerConfiguration(
                scrollerStyle: .overlay,
                autohidesScrollers: true,
                controlSize: .regular
            )
        case (.utilityPanel, .legacy):
            AppScrollerConfiguration(
                scrollerStyle: .legacy,
                autohidesScrollers: false,
                controlSize: .small
            )
        case (.utilityPanel, .overlay):
            AppScrollerConfiguration(
                scrollerStyle: .overlay,
                autohidesScrollers: true,
                controlSize: .small
            )
        @unknown default:
            configuration(for: role, preferredStyle: .overlay)
        }
    }
}
