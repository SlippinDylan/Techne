//
//  ClickablePathLabel.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 可点击的路径标签
/// 点击后在 Finder 中显示该路径
struct ClickablePathLabel: View {
    let path: String
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }) {
            HStack(spacing: AppConfig.UI.smallSpacing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                Text(displayPath)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? Color.blue : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var displayPath: String {
        guard !path.isEmpty else { return path }
        let username = NSUserName()
        guard !username.isEmpty else { return path }
        let userHomePath = "/Users/\(username)"

        if path == userHomePath {
            return "~"
        } else if path.hasPrefix(userHomePath + "/") {
            return "~" + path.dropFirst(userHomePath.count)
        }
        return path
    }
}
