import SwiftUI

struct ConsolePanelContainer<HeaderContent: View, Content: View>: View {
    private let configuration: ConsolePanelStyle.Configuration
    private let headerMode: HeaderMode
    @ViewBuilder private let content: () -> Content

    init(
        configuration: ConsolePanelStyle.Configuration,
        showsHeaderDivider: Bool? = nil,
        @ViewBuilder header: @escaping () -> HeaderContent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.configuration = configuration
        self.headerMode = .visible(
            showsDivider: showsHeaderDivider ?? configuration.shell.showsHeaderDivider,
            content: header
        )
        self.content = content
    }

    var body: some View {
        let bodyContent = Group {
            switch headerMode {
            case .hidden:
                content()

            case .visible(let showsDivider, let header):
                VStack(alignment: .leading, spacing: configuration.shell.headerSpacing) {
                    header()

                    if showsDivider {
                        Divider()
                            .overlay(headerDividerColor)
                    }

                    content()
                }
            }
        }

        if configuration.showsShellChrome {
            bodyContent
                .padding(configuration.shell.contentPadding)
                .background(shellBackgroundColor)
                .clipShape(
                    RoundedRectangle(cornerRadius: configuration.shell.outerCornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: configuration.shell.outerCornerRadius)
                        .stroke(shellBorderColor, lineWidth: 1)
                )
        } else {
            bodyContent
        }
    }

    private var shellBackgroundColor: Color {
        configuration.palette.shellBackground.resolvedColor
    }

    private var shellBorderColor: Color {
        configuration.palette.shellBorder.resolvedColor
    }

    private var headerDividerColor: Color {
        configuration.palette.headerDivider.resolvedColor
    }

    private enum HeaderMode {
        case hidden
        case visible(
            showsDivider: Bool,
            content: () -> HeaderContent
        )
    }
}

extension ConsolePanelContainer where HeaderContent == EmptyView {
    init(
        configuration: ConsolePanelStyle.Configuration,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.configuration = configuration
        self.headerMode = .hidden
        self.content = content
    }
}
