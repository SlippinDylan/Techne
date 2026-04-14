//
//  BrowserDetectionService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation
import AppKit

class BrowserDetectionService {

    // 获取系统默认浏览器的 Bundle ID
    func getDefaultBrowserBundleId() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.LaunchServices/com.apple.launchservices.secure", "LSHandlers"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "BrowserDetectionService")

            guard terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 查找 http 或 https 协议的处理程序
                // 使用更精确的正则表达式，确保匹配的是 http/https 协议
                let pattern = #"LSHandlerURLScheme\s*=\s*"?https?"?;[^}]*LSHandlerRoleAll\s*=\s*"([^"]+)";"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                   let match = regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output)),
                   let bundleIdRange = Range(match.range(at: 1), in: output) {
                    return String(output[bundleIdRange])
                }
            }
        } catch {
        }

        return nil
    }

    // 检测系统中安装的所有浏览器
    func detectInstalledBrowsers() -> [Browser] {
        var browsers: [Browser] = []
        let defaultBundleId = getDefaultBrowserBundleId()

        for browserType in BrowserType.allCases {
            if let path = findBrowserPath(for: browserType) {
                let isDefault = (browserType.bundleId == defaultBundleId)
                let browser = Browser(type: browserType, path: path, isDefault: isDefault)
                browsers.append(browser)
            }
        }

        // 将默认浏览器排在第一位
        browsers.sort { $0.isDefault && !$1.isDefault }

        return browsers
    }

    // 查找浏览器的实际路径
    private func findBrowserPath(for browserType: BrowserType) -> String? {
        for path in browserType.possiblePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }
        return nil
    }
}
