//
//  CleanMyMacButton.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI

struct CleanMyMacButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    var style: CleanMyMacButtonStyle = .primary
    var isDestructive: Bool = false

    enum CleanMyMacButtonStyle {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))
                }
                Text(title)
                    .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))
            }
        }
        .modify { view in
            if style == .primary {
                view.buttonStyle(.glassProminent)
            } else {
                view.buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.capsule)
        .tint(isDestructive ? .red : nil)
    }
}

// MARK: - View Modifier Helper

extension View {
    @ViewBuilder
    func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}
