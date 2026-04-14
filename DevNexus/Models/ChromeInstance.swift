//
//  ChromeInstance.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/13.
//

import Foundation
import AppKit

struct ChromeInstance: Identifiable, Equatable {
    let id: Int32 // PID
    let processName: String
    let url: String
    let debugPort: Int?
    let commandLine: String
    let startTime: Date

    var displayName: String {
        if url.isEmpty {
            return processName
        }
        return url
    }

    var hasDebugPort: Bool {
        debugPort != nil
    }

    // 获取应用图标
    var appIcon: NSImage? {
        // 从 commandLine 中提取应用路径
        // commandLine 格式类似: /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
        let appPath = extractAppPath(from: commandLine)

        if !appPath.isEmpty {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        return nil
    }

    // 从命令行路径中提取 .app 路径
    private func extractAppPath(from path: String) -> String {
        guard let range = path.range(of: ".app") else { return "" }
        return String(path[..<range.upperBound])
    }

    static func == (lhs: ChromeInstance, rhs: ChromeInstance) -> Bool {
        lhs.id == rhs.id
    }
}
