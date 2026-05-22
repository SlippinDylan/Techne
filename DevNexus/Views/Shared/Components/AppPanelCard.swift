//
//  AppPanelCard.swift
//  DevNexus
//
//  Created by OpenAI Codex on 2026/05/20.
//

import SwiftUI

struct AppPanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GroupBox {
            content
        }
    }
}
