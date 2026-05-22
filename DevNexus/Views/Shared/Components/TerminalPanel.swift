import SwiftUI

struct TerminalPanel<ToolbarContent: View>: View {
    let output: String
    let emptyText: String
    let height: CGFloat?
    let showsToolbar: Bool
    @ViewBuilder let toolbarContent: () -> ToolbarContent

    init(
        output: String,
        emptyText: String,
        height: CGFloat? = nil,
        showsToolbar: Bool = true,
        @ViewBuilder toolbarContent: @escaping () -> ToolbarContent
    ) {
        self.output = output
        self.emptyText = emptyText
        self.height = height
        self.showsToolbar = showsToolbar
        self.toolbarContent = toolbarContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.mediumSpacing) {
            if showsToolbar {
                toolbarContent()
            }
            terminalBody
        }
    }

    private var terminalBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayedText)
                        .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                        .foregroundStyle(output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppConfig.UI.mediumSpacing)

                    Color.clear
                        .frame(height: 1)
                        .id("terminalBottom")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modify { view in
                if let height {
                    view.frame(height: height)
                } else {
                    view
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onChange(of: output) { _, _ in
                proxy.scrollTo("terminalBottom", anchor: .bottom)
            }
        }
    }

    private var displayedText: String {
        output.isEmpty ? emptyText : output
    }
}

extension TerminalPanel where ToolbarContent == EmptyView {
    init(
        output: String,
        emptyText: String,
        height: CGFloat? = nil
    ) {
        self.init(output: output, emptyText: emptyText, height: height, showsToolbar: false) {
            EmptyView()
        }
    }
}
