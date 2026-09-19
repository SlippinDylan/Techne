import SwiftUI

struct StartupModePicker: View {
    let modes: [ProjectStartupMode]
    let selectedModeID: String?
    let isDisabled: Bool
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(modes) { mode in
                Button {
                    onSelect(mode.id)
                } label: {
                    if mode.id == selectedModeID {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            Text(currentLabel)
                .font(.system(size: AppConfig.UI.smallFontSize))
                .padding(.horizontal, AppConfig.UI.mediumSpacing)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
        }
        .disabled(isDisabled || modes.count <= 1)
    }

    private var currentLabel: String {
        modes.first(where: { $0.id == selectedModeID })?.displayName ?? AppLocalized("默认")
    }
}
