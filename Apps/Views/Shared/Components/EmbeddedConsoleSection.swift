import SwiftUI

struct EmbeddedConsoleSection: View {
    static let outerPadding = AppConfig.UI.mediumPadding

    let output: String
    let emptyText: String
    let height: CGFloat?
    let outerPadding: CGFloat

    private let configuration = ConsolePanelStyle.configuration(for: .embeddedTerminal)

    init(
        output: String,
        emptyText: String,
        height: CGFloat? = nil,
        outerPadding: CGFloat = EmbeddedConsoleSection.outerPadding
    ) {
        self.output = output
        self.emptyText = emptyText
        self.height = height
        self.outerPadding = outerPadding
    }

    var body: some View {
        TerminalPanel(
            output: output,
            emptyText: emptyText,
            height: height,
            configuration: configuration
        )
        .padding(outerPadding)
    }
}
