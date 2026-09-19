import SwiftUI

struct StartupModePicker: View {
    let modes: [ProjectStartupMode]
    let selectedModeID: String?
    let isDisabled: Bool
    let onSelect: (String) -> Void
    @State private var isHovered = false
    @State private var isShowingOptions = false

    var body: some View {
        Button {
            isShowingOptions.toggle()
        } label: {
            HStack(spacing: AppConfig.UI.smallSpacing) {
                Text(currentLabel)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppConfig.UI.smallFontSize - 2, weight: .semibold))
            }
            .padding(.horizontal, AppConfig.UI.smallPadding)
            .padding(.vertical, 3)
            .background(
                Color.secondary.opacity(isHovered && !isPickerDisabled ? 0.14 : 0.08),
                in: Capsule()
            )
            .foregroundStyle(isHovered && !isPickerDisabled ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isPickerDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isShowingOptions, arrowEdge: .top) {
            optionsPopover
        }
    }

    private var currentLabel: String {
        modes.first(where: { $0.id == selectedModeID })?.displayName ?? AppLocalized("默认")
    }

    private var isPickerDisabled: Bool {
        isDisabled || modes.count <= 1
    }

    private var optionsPopover: some View {
        VStack(spacing: AppConfig.UI.smallSpacing) {
            ForEach(modes) { mode in
                optionButton(for: mode)
            }
        }
        .padding(AppConfig.UI.smallPadding)
        .frame(minWidth: 160)
    }

    private func optionButton(for mode: ProjectStartupMode) -> some View {
        let isSelected = mode.id == selectedModeID

        return Button {
            isShowingOptions = false
            guard !isSelected else { return }
            onSelect(mode.id)
        } label: {
            HStack(spacing: AppConfig.UI.mediumSpacing) {
                Text(mode.displayName)
                    .font(.system(size: AppConfig.UI.mediumFontSize))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: AppConfig.UI.smallFontSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, AppConfig.UI.mediumPadding)
            .padding(.vertical, AppConfig.UI.mediumSpacing)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
        }
        .buttonStyle(.plain)
    }
}
