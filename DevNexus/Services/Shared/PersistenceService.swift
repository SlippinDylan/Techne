//
//  PersistenceService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 通用持久化服务
/// 数据存放在 ~/Library/Application Support/<bundle-id>/
final class PersistenceService<T: Codable & Sendable>: Sendable {
    let storageURL: URL

    init(filename: String, directoryURL: URL? = nil) {
        let fileManager = FileManager.default
        let baseDirectoryURL: URL

        if let directoryURL {
            baseDirectoryURL = directoryURL
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? "studio.slippindylan.DevNexus"
            baseDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(bundleID, isDirectory: true)
        }

        try? fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        self.storageURL = baseDirectoryURL.appendingPathComponent(filename)
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
