//
//  Browser.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation
import AppKit

enum BrowserEngine: Sendable {
    case chromium
    case safari
}

// 浏览器类型
enum BrowserType: String, Identifiable, Sendable {
    case chrome = "Google Chrome"
    case chromeBeta = "Chrome Beta"
    case chromium = "Chromium"
    case edge = "Microsoft Edge"
    case safari = "Safari"
    case brave = "Brave"
    case arc = "Arc"

    var id: String { rawValue }

    static let detectionCandidates: [BrowserType] = [
        .safari,
        .chrome,
        .chromeBeta,
        .chromium,
        .edge,
        .brave,
        .arc
    ]

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

    var engine: BrowserEngine {
        switch self {
        case .safari:
            return .safari
        default:
            return .chromium
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

    var supportsManagedInstances: Bool {
        engine == .chromium
    }

    var supportsRemoteDebugging: Bool {
        engine == .chromium
    }

    var supportsNewApplicationInstance: Bool {
        engine == .chromium
    }
}

// 浏览器信息
struct Browser: Identifiable, Hashable, Sendable {
    let type: BrowserType
    let appURL: URL
    let isDefault: Bool

    private var canonicalAppURL: URL {
        appURL.resolvingSymlinksInPath().standardizedFileURL
    }

    var appPath: String {
        canonicalAppURL.path
    }

    // 使用 bundleId + appURL 作为稳定的标识符
    var id: String {
        "\(type.bundleId)_\(appPath)"
    }

    var displayName: String {
        type.rawValue
    }

    var sortName: String {
        type.rawValue
    }

    // 获取应用图标
    var appIcon: NSImage? {
        guard FileManager.default.fileExists(atPath: appPath) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appPath)
    }

    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(type.bundleId)
        hasher.combine(appPath)
    }

    static func == (lhs: Browser, rhs: Browser) -> Bool {
        lhs.type.bundleId == rhs.type.bundleId && lhs.appPath == rhs.appPath
    }
}
