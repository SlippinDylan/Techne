//
//  Browser.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation
import AppKit

// 浏览器类型
enum BrowserType: String, CaseIterable, Identifiable {
    case chrome = "Google Chrome"
    case chromeBeta = "Chrome Beta"
    case chromium = "Chromium"
    case edge = "Microsoft Edge"
    case safari = "Safari"
    case brave = "Brave"
    case arc = "Arc"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chrome, .chromeBeta, .chromium:
            return "globe"
        case .edge:
            return "globe"
        case .safari:
            return "safari"
        case .brave:
            return "shield"
        case .arc:
            return "globe"
        }
    }

    // 可能的安装路径
    var possiblePaths: [String] {
        switch self {
        case .chrome:
            return [
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                "~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            ]
        case .chromeBeta:
            return [
                "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta",
                "~/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta"
            ]
        case .chromium:
            return [
                "/Applications/Chromium.app/Contents/MacOS/Chromium",
                "~/Applications/Chromium.app/Contents/MacOS/Chromium"
            ]
        case .edge:
            return [
                "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
                "~/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
            ]
        case .safari:
            return [
                "/Applications/Safari.app/Contents/MacOS/Safari",
                "/System/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari"
            ]
        case .brave:
            return [
                "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
                "~/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
            ]
        case .arc:
            return [
                "/Applications/Arc.app/Contents/MacOS/Arc",
                "~/Applications/Arc.app/Contents/MacOS/Arc"
            ]
        }
    }

    // Bundle ID
    var bundleId: String {
        switch self {
        case .chrome:
            return "com.google.Chrome"
        case .chromeBeta:
            return "com.google.Chrome.beta"
        case .chromium:
            return "org.chromium.Chromium"
        case .edge:
            return "com.microsoft.edgemac"
        case .safari:
            return "com.apple.Safari"
        case .brave:
            return "com.brave.Browser"
        case .arc:
            return "company.thebrowser.Browser"
        }
    }
}

// 浏览器信息
struct Browser: Identifiable, Hashable {
    let type: BrowserType
    let path: String
    let isDefault: Bool

    // 使用 bundleId + path 作为稳定的标识符
    var id: String {
        "\(type.bundleId)_\(path)"
    }

    var displayName: String {
        isDefault ? "\(type.rawValue) (默认)" : type.rawValue
    }

    // 获取应用图标
    var appIcon: NSImage? {
        // 使用正则表达式提取 .app 路径
        let pattern = "^(.*\\.app)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // 正则表达式创建失败，使用备用方案
            if let appRange = path.range(of: ".app") {
                let appPath = String(path[..<appRange.upperBound])
                return NSWorkspace.shared.icon(forFile: appPath)
            }
            return nil
        }

        guard let match = regex.firstMatch(in: path, options: [], range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range, in: path) else {
            // 正则匹配失败，使用备用方案
            if let appRange = path.range(of: ".app") {
                let appPath = String(path[..<appRange.upperBound])
                return NSWorkspace.shared.icon(forFile: appPath)
            }
            return nil
        }

        let appPath = String(path[range])

        // 验证路径是否存在
        guard FileManager.default.fileExists(atPath: appPath) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appPath)
    }

    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(type.bundleId)
        hasher.combine(path)
    }

    static func == (lhs: Browser, rhs: Browser) -> Bool {
        lhs.type.bundleId == rhs.type.bundleId && lhs.path == rhs.path
    }
}
