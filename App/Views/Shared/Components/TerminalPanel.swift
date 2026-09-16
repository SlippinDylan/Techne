import SwiftUI

struct TerminalPanel<ToolbarContent: View>: View {
    private let output: String
    private let emptyText: String
    private let explicitHeight: CGFloat?
    private let configuration: ConsolePanelStyle.Configuration
    @ViewBuilder let toolbarContent: () -> ToolbarContent

    init(
        output: String,
        emptyText: String,
        height: CGFloat? = nil,
        configuration: ConsolePanelStyle.Configuration = ConsolePanelStyle.configuration(for: .embeddedTerminal),
        @ViewBuilder toolbarContent: @escaping () -> ToolbarContent
    ) {
        self.output = output
        self.emptyText = emptyText
        self.explicitHeight = height
        self.configuration = configuration
        self.toolbarContent = toolbarContent
    }

    var body: some View {
        Group {
            if ToolbarContent.self == EmptyView.self {
                ConsolePanelContainer(configuration: configuration) {
                    terminalViewport
                }
            } else {
                ConsolePanelContainer(configuration: configuration) {
                    toolbarContent()
                } content: {
                    terminalViewport
                }
            }
        }
    }

    private var terminalViewport: some View {
        ConsoleTextViewport(
            text: displayedText,
            isPlaceholder: output.isEmpty,
            padding: configuration.viewport.padding
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modify { view in
                if let explicitHeight {
                    view.frame(height: explicitHeight)
                } else {
                    switch configuration.viewport.sizing {
                    case .fixed(let height):
                        view.frame(height: height)
                    case .flexible:
                        view
                    }
                }
            }
            .background(configuration.palette.viewportBackground.resolvedColor)
            .clipShape(RoundedRectangle(cornerRadius: configuration.viewport.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: configuration.viewport.cornerRadius)
                    .stroke(configuration.palette.viewportBorder.resolvedColor, lineWidth: 1)
            )
    }

    private var displayedText: String {
        output.isEmpty ? emptyText : output
    }
}

extension TerminalPanel where ToolbarContent == EmptyView {
    init(
        output: String,
        emptyText: String,
        height: CGFloat? = nil,
        configuration: ConsolePanelStyle.Configuration = ConsolePanelStyle.configuration(for: .embeddedTerminal)
    ) {
        self.output = output
        self.emptyText = emptyText
        self.explicitHeight = height
        self.configuration = configuration
        self.toolbarContent = { EmptyView() }
    }
}
