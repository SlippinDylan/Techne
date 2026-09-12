import Foundation

enum ConsolePanelStyle {
    static let embeddedTerminalViewportHeight: CGFloat = 200

    enum Role {
        case embeddedTerminal
        case logWindow
    }

    enum ColorToken: Equatable {
        case cardBackground
        case textBackground
        case separator
    }

    enum ViewportSizing: Equatable {
        case fixed(CGFloat)
        case flexible
    }

    struct ShellMetrics: Equatable {
        let outerCornerRadius: CGFloat
        let contentPadding: CGFloat
        let headerSpacing: CGFloat
        let showsHeaderDivider: Bool
    }

    struct ViewportMetrics: Equatable {
        let cornerRadius: CGFloat
        let padding: CGFloat
        let sizing: ViewportSizing
    }

    struct Palette: Equatable {
        let shellBackground: ColorToken
        let shellBorder: ColorToken
        let headerDivider: ColorToken
        let viewportBackground: ColorToken
        let viewportBorder: ColorToken
    }

    struct Configuration: Equatable {
        let shell: ShellMetrics
        let viewport: ViewportMetrics
        let palette: Palette

        var showsShellChrome: Bool {
            shell.outerCornerRadius > 0 || shell.contentPadding > 0
        }
    }

    static let sharedPalette = Palette(
        shellBackground: .cardBackground,
        shellBorder: .separator,
        headerDivider: .separator,
        viewportBackground: .textBackground,
        viewportBorder: .separator
    )

    static func configuration(for role: Role) -> Configuration {
        switch role {
        case .embeddedTerminal:
            return Configuration(
                shell: ShellMetrics(
                    outerCornerRadius: 0,
                    contentPadding: 0,
                    headerSpacing: AppConfig.UI.mediumSpacing,
                    showsHeaderDivider: true
                ),
                viewport: ViewportMetrics(
                    cornerRadius: AppConfig.UI.mediumCornerRadius,
                    padding: AppConfig.UI.mediumPadding,
                    sizing: .fixed(embeddedTerminalViewportHeight)
                ),
                palette: sharedPalette
            )

        case .logWindow:
            return Configuration(
                shell: ShellMetrics(
                    outerCornerRadius: AppConfig.UI.largeCornerRadius,
                    contentPadding: AppConfig.UI.mediumPadding,
                    headerSpacing: AppConfig.UI.largeSpacing,
                    showsHeaderDivider: false
                ),
                viewport: ViewportMetrics(
                    cornerRadius: AppConfig.UI.mediumCornerRadius,
                    padding: AppConfig.UI.mediumPadding,
                    sizing: .flexible
                ),
                palette: sharedPalette
            )
        }
    }
}
