//
//  BrowserDetectionService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation
import AppKit
import CoreServices
import Observation

protocol BrowserApplicationWorkspace {
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func urlsForApplications(withBundleIdentifier bundleIdentifier: String) -> [URL]
}

extension NSWorkspace: BrowserApplicationWorkspace {}

@MainActor
@Observable
final class BrowserDetectionService {
    var installedBrowsers: [Browser] = []

    nonisolated private static let browserResolutionURL = URL(string: "https://localhost")!

    private let workspace: BrowserApplicationWorkspace
    private let fileManager: FileManager
    private let defaultBrowserBundleIDProvider: () -> String?

    init(
        workspace: BrowserApplicationWorkspace = NSWorkspace.shared,
        fileManager: FileManager = .default,
        defaultBrowserBundleIDProvider: @escaping () -> String? = BrowserDetectionService.resolveDefaultBrowserBundleID
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.defaultBrowserBundleIDProvider = defaultBrowserBundleIDProvider
    }

    func refresh() {
        installedBrowsers = detectInstalledBrowsers()
    }

    func refreshIfNeeded() {
        guard installedBrowsers.isEmpty else { return }
        refresh()
    }

    nonisolated static func resolveDefaultBrowserBundleID() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: browserResolutionURL) else {
            return nil
        }

        return Bundle(url: appURL)?.bundleIdentifier
    }

    // 获取系统默认浏览器的 Bundle ID
    func getDefaultBrowserBundleId() -> String? {
        defaultBrowserBundleIDProvider()
    }

    // 检测系统中安装的所有浏览器
    func detectInstalledBrowsers() -> [Browser] {
        let defaultBundleId = getDefaultBrowserBundleId()

        return BrowserType.detectionCandidates.compactMap { browserType in
            guard let appURL = resolvedApplicationURL(for: browserType) else {
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

            return lhs.sortName.localizedStandardCompare(rhs.sortName) == .orderedAscending
        }
    }

    private func resolvedApplicationURL(for browserType: BrowserType) -> URL? {
        let preferredURL = workspace.urlForApplication(withBundleIdentifier: browserType.bundleId)
        let discoveredURLs = workspace.urlsForApplications(withBundleIdentifier: browserType.bundleId)

        for candidate in deduplicatedCandidateURLs(preferredURL: preferredURL, discoveredURLs: discoveredURLs) {
            if isInstalledApplication(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func deduplicatedCandidateURLs(preferredURL: URL?, discoveredURLs: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        var candidates: [URL] = []

        for rawURL in [preferredURL] + discoveredURLs {
            guard let canonicalURL = canonicalApplicationURL(from: rawURL) else {
                continue
            }

            let canonicalPath = canonicalURL.path
            guard seenPaths.insert(canonicalPath).inserted else {
                continue
            }

            candidates.append(canonicalURL)
        }

        return candidates
    }

    private func canonicalApplicationURL(from rawURL: URL?) -> URL? {
        guard let rawURL else { return nil }

        let canonicalURL = rawURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }

        return canonicalURL
    }

    private func isInstalledApplication(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
