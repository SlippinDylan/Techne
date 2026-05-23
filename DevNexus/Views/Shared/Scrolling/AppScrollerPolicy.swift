import AppKit

enum AppScrollSurfaceRole {
    case mainContent
    case utilityPanel
    case consoleViewport
}

struct AppScrollerConfiguration: Equatable {
    let scrollerStyle: NSScroller.Style
    let autohidesScrollers: Bool
    let controlSize: NSControl.ControlSize
}

enum AppScrollerPolicy {
    static func configuration(
        for role: AppScrollSurfaceRole,
        preferredStyle _: NSScroller.Style = NSScroller.preferredScrollerStyle
    ) -> AppScrollerConfiguration {
        switch role {
        case .mainContent, .utilityPanel, .consoleViewport:
            AppScrollerConfiguration(
                scrollerStyle: .overlay,
                autohidesScrollers: true,
                controlSize: .regular
            )
        }
    }
}
