import SwiftUI
import UniformTypeIdentifiers

private struct ProjectInputFieldSurfaceModifier: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppConfig.UI.mediumPadding)
            .frame(height: height)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

extension View {
    func projectInputFieldSurface(height: CGFloat = 44) -> some View {
        modifier(ProjectInputFieldSurfaceModifier(height: height))
    }
}

struct InteractivePathField<TrailingContent: View>: View {
    let leadingSystemImage: String
    let text: String?
    let placeholder: String
    let usesMonospacedText: Bool
    let height: CGFloat
    let acceptedDropTypes: [String]
    let action: () -> Void
    let onDropProviders: (([NSItemProvider]) -> Bool)?
    @ViewBuilder let trailingContent: () -> TrailingContent

    init(
        leadingSystemImage: String,
        text: String?,
        placeholder: String,
        usesMonospacedText: Bool = true,
        height: CGFloat = 44,
        acceptedDropTypes: [String] = [UTType.fileURL.identifier],
        action: @escaping () -> Void,
        onDropProviders: (([NSItemProvider]) -> Bool)? = nil,
        @ViewBuilder trailingContent: @escaping () -> TrailingContent
    ) {
        self.leadingSystemImage = leadingSystemImage
        self.text = text
        self.placeholder = placeholder
        self.usesMonospacedText = usesMonospacedText
        self.height = height
        self.acceptedDropTypes = acceptedDropTypes
        self.action = action
        self.onDropProviders = onDropProviders
        self.trailingContent = trailingContent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppConfig.UI.mediumSpacing) {
                Image(systemName: leadingSystemImage)
                    .foregroundStyle(Color.accentColor)

                if let text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Text(text)
                        .font(textFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(placeholder)
                        .font(textFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppConfig.UI.mediumSpacing)
                trailingContent()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .projectInputFieldSurface(height: height)
        .modify { view in
            if let onDropProviders {
                view.onDrop(of: acceptedDropTypes, isTargeted: nil, perform: onDropProviders)
            } else {
                view
            }
        }
    }

    private var textFont: Font {
        if usesMonospacedText {
            return .system(.body, design: .monospaced)
        }

        return .system(size: AppConfig.UI.mediumFontSize)
    }
}

extension InteractivePathField where TrailingContent == EmptyView {
    init(
        leadingSystemImage: String,
        text: String?,
        placeholder: String,
        usesMonospacedText: Bool = true,
        height: CGFloat = 44,
        acceptedDropTypes: [String] = [UTType.fileURL.identifier],
        action: @escaping () -> Void,
        onDropProviders: (([NSItemProvider]) -> Bool)? = nil
    ) {
        self.init(
            leadingSystemImage: leadingSystemImage,
            text: text,
            placeholder: placeholder,
            usesMonospacedText: usesMonospacedText,
            height: height,
            acceptedDropTypes: acceptedDropTypes,
            action: action,
            onDropProviders: onDropProviders
        ) {
            EmptyView()
        }
    }
}
