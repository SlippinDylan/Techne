//
//  BrowserDetectionService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation
import AppKit
import CoreServices

class BrowserDetectionService {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    // 获取系统默认浏览器的 Bundle ID
    func getDefaultBrowserBundleId() -> String? {
        if let httpsHandler = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() {
            return httpsHandler as String
        }

        if let httpHandler = LSCopyDefaultHandlerForURLScheme("http" as CFString)?.takeRetainedValue() {
            return httpHandler as String
        }

        return nil
    }

    // 检测系统中安装的所有浏览器
    func detectInstalledBrowsers() -> [Browser] {
        let defaultBundleId = getDefaultBrowserBundleId()

        return BrowserType.allCases.compactMap { browserType in
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: browserType.bundleId) else {
                return nil
            }

            return Browser(
                type: browserType,
                appURL: appURL,
                isDefault: browserType.bundleId == defaultBundleId
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }

            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}
