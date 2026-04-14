//
//  LogService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation
import Observation

/// 日志级别
enum LogLevel: String, Codable, Sendable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error = "ERROR"

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

/// 日志条目
struct LogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let category: String

    init(level: LogLevel, message: String, category: String = "General") {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.category = category
    }

    var formattedTimestamp: String {
        timestamp.formatted(date: .omitted, time: .standard)
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, level, message, category
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.level = try container.decode(LogLevel.self, forKey: .level)
        self.message = try container.decode(String.self, forKey: .message)
        self.category = try container.decode(String.self, forKey: .category)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(message, forKey: .message)
        try container.encode(category, forKey: .category)
    }
}

// MARK: - 全局日志入口 (解决 Swift 6 静态属性隔离冲突)

/// 全局日志辅助函数
func AppLogInfo(_ message: String, category: String = "General") { 
    Task { @MainActor in LogService.shared.addLog(level: .info, message: message, category: category) }
}
func AppLogSuccess(_ message: String, category: String = "General") { 
    Task { @MainActor in LogService.shared.addLog(level: .success, message: message, category: category) }
}
func AppLogWarning(_ message: String, category: String = "General") { 
    Task { @MainActor in LogService.shared.addLog(level: .warning, message: message, category: category) }
}
func AppLogError(_ message: String, category: String = "General") { 
    Task { @MainActor in LogService.shared.addLog(level: .error, message: message, category: category) }
}

/// 日志服务
@MainActor
@Observable
final class LogService {
    // 使用 MainActor 隔离单例，这是最安全的
    static let shared = LogService()

    var logs: [LogEntry] = []
    private let maxLogCount = 500
    private let persistenceService: PersistenceService<LogEntry>

    private init() {
        // 由于 init 在 MainActor，我们可以安全地在主线程完成初始化
        persistenceService = PersistenceService(filename: "logs.json")
        logs = persistenceService.load()
    }

    // MARK: - Public Methods

    func info(_ message: String, category: String = "General") { addLog(level: .info, message: message, category: category) }
    func success(_ message: String, category: String = "General") { addLog(level: .success, message: message, category: category) }
    func warning(_ message: String, category: String = "General") { addLog(level: .warning, message: message, category: category) }
    func error(_ message: String, category: String = "General") { addLog(level: .error, message: message, category: category) }

    func clearLogs() {
        logs.removeAll()
        saveLogs()
    }

    // MARK: - Internal Methods

    func addLog(level: LogLevel, message: String, category: String) {
        let entry = LogEntry(level: level, message: message, category: category)
        logs.insert(entry, at: 0)
        if logs.count > maxLogCount { logs.removeLast(logs.count - maxLogCount) }
        saveLogs()
    }

    private func saveLogs() {
        _ = persistenceService.save(logs)
    }
}
