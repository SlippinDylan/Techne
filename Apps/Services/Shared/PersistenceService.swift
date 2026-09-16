//
//  PersistenceService.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 持久化根目录策略。
/// 默认使用 ~/Library/Application Support/<bundle-id>/，测试场景可显式注入隔离目录。
struct PersistenceRoot: Sendable {
    let directoryURL: URL

    static func applicationSupport(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        fallbackBundleIdentifier: String = "studio.slippindylan.Techne"
    ) -> PersistenceRoot {
        let resolvedBundleIdentifier = bundleIdentifier ?? fallbackBundleIdentifier
        let directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(resolvedBundleIdentifier, isDirectory: true)
        return PersistenceRoot(directoryURL: directoryURL)
    }

    static func custom(_ directoryURL: URL) -> PersistenceRoot {
        PersistenceRoot(directoryURL: directoryURL)
    }
}

/// 预览场景的临时持久化租约。
/// 生命周期结束时自动清理隔离目录，避免测试和 Preview 累积垃圾目录。
@MainActor
final class PreviewPersistenceSession {
    let persistenceRoot: PersistenceRoot

    init(
        fileManager: FileManager = .default,
        sessionID: String = ProcessInfo.processInfo.globallyUniqueString
    ) {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("Techne/Previews", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.persistenceRoot = .custom(directoryURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: persistenceRoot.directoryURL)
    }
}

/// 通用持久化服务
/// 数据存放在 ~/Library/Application Support/<bundle-id>/
struct PersistenceService<T: Codable & Sendable>: Sendable {
    let storageURL: URL

    init(filename: String, root: PersistenceRoot = .applicationSupport()) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: root.directoryURL, withIntermediateDirectories: true)
        self.storageURL = root.directoryURL.appendingPathComponent(filename)
    }

    func load() -> [T] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            return try decoder.decode([T].self, from: data)
        } catch {
            print("⚠️ 加载数据失败：\(error.localizedDescription)")
            return []
        }
    }

    func save(_ items: [T]) -> Result<Void, ProjectServiceError> {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            try data.write(to: storageURL, options: .atomic)
            return .success(())
        } catch {
            return .failure(.persistenceFailed(error.localizedDescription))
        }
    }
}
