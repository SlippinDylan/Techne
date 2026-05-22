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
    let launchTarget: BrowserLaunchTarget?

    var displayName: String {
        if url.isEmpty {
            return processName
        }
        return url
    }

    var hasDebugPort: Bool {
        debugPort != nil
    }

    func isRelated(to server: DevServer) -> Bool {
        if let launchTarget {
            return launchTarget.matches(server: server)
        }

        guard let launchedPort = launchedPort else {
            return false
        }

        return launchedPort == server.port
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

    private var launchedPort: Int? {
        if let port = URLComponents(string: url)?.port {
            return port
        }

        guard let range = url.range(of: #":(\d+)"#, options: .regularExpression) else {
            return nil
        }

        return Int(url[range].dropFirst())
    }

    static func == (lhs: ChromeInstance, rhs: ChromeInstance) -> Bool {
        lhs.id == rhs.id
    }
}
