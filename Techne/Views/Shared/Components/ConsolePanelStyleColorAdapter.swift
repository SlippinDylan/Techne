import SwiftUI

extension ConsolePanelStyle.ColorToken {
    var resolvedColor: Color {
        switch self {
        case .cardBackground:
            return .cardBackground
        case .textBackground:
            return Color(nsColor: .textBackgroundColor)
        case .separator:
            return Color(nsColor: .separatorColor)
        }
    }
}
