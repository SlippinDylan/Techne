//
//  Project.swift
//  DevNexus
//
//  统一的项目模型 (Phase 4 适配版)
//

import Foundation

enum ProjectTransitionState: String, Sendable {
    case idle
    case installing
    case starting
    case stopping
}

enum InstallStrategy: String, Codable, Sendable {
    case never
    case ifMissing
    case always
}

// MARK: - ProjectType Extension

extension ProjectType {
    /// 默认启动命令
    var defaultStartCommand: String {
        switch self {
        case .devServer:
            return "pnpm dev"
        case .miniApp:
            return "pnpm dev:mp"
        }
    }
}

/// 统一的项目模型
/// 显式标记为 Sendable 并自定义 Codable 实现以解除隐式 MainActor 隔离
struct Project: Identifiable, Codable, Equatable, Sendable {
    // MARK: - 持久化属性

    let id: UUID
    var name: String
    var path: String
    var type: ProjectType
    var currentBranch: String
    var startCommand: String
    var buildCommand: String
    var cleanCommand: String
    var installCommand: String
    var stopCommand: String
    var discardChangesCommand: String
    var commandProfileName: String?
    var installStrategy: InstallStrategy
    var commandConfigId: UUID?
    let addedDate: Date

    // MARK: - 运行时状态（不持久化）

    var isRunning: Bool = false
    var runningProcessPID: Int32? = nil
    var uncommittedFileCount: Int = 0
    var terminalOutput: String = ""
    var transitionState: ProjectTransitionState = .idle

    // MARK: - 初始化

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        type: ProjectType,
        currentBranch: String = "",
        startCommand: String? = nil,
        buildCommand: String = "",
        cleanCommand: String = "",
        installCommand: String = "",
        stopCommand: String = "",
        discardChangesCommand: String = "",
        commandProfileName: String? = nil,
        installStrategy: InstallStrategy = .ifMissing,
        commandConfigId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.currentBranch = currentBranch
        self.startCommand = startCommand ?? type.defaultStartCommand
        self.buildCommand = buildCommand
        self.cleanCommand = cleanCommand
        self.installCommand = installCommand
        self.stopCommand = stopCommand
        self.discardChangesCommand = discardChangesCommand
        self.commandProfileName = commandProfileName
        self.installStrategy = installStrategy
        self.commandConfigId = commandConfigId
        self.addedDate = Date()

        // 运行时状态初始化
        self.isRunning = false
        self.runningProcessPID = nil
        self.uncommittedFileCount = 0
        self.terminalOutput = ""
        self.transitionState = .idle
    }

    // MARK: - 计算属性

    var displayPath: String {
        guard !path.isEmpty else { return path }
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDirectory) {
            if path == homeDirectory {
                return "~"
            } else if path.hasPrefix(homeDirectory + "/") {
                return "~" + path.dropFirst(homeDirectory.count)
            }
        }
        return path
    }

    // MARK: - Equatable

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case type
        case currentBranch
        case startCommand
        case buildCommand
        case cleanCommand
        case installCommand
        case stopCommand
        case discardChangesCommand
        case commandProfileName
        case installStrategy
        case commandConfigId
        case addedDate
    }

    /// 显式非隔离初始化，解除 MainActor 隐式推断
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
        self.type = try container.decode(ProjectType.self, forKey: .type)
        self.currentBranch = try container.decode(String.self, forKey: .currentBranch)
        self.startCommand = try container.decode(String.self, forKey: .startCommand)
        self.buildCommand = try container.decodeIfPresent(String.self, forKey: .buildCommand) ?? ""
        self.cleanCommand = try container.decodeIfPresent(String.self, forKey: .cleanCommand) ?? ""
        self.installCommand = try container.decodeIfPresent(String.self, forKey: .installCommand) ?? ""
        self.stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand) ?? ""
        self.discardChangesCommand = try container.decodeIfPresent(String.self, forKey: .discardChangesCommand) ?? ""
        self.commandProfileName = try container.decodeIfPresent(String.self, forKey: .commandProfileName)
        self.installStrategy = try container.decodeIfPresent(InstallStrategy.self, forKey: .installStrategy) ?? .ifMissing
        self.commandConfigId = try container.decodeIfPresent(UUID.self, forKey: .commandConfigId)
        self.addedDate = try container.decode(Date.self, forKey: .addedDate)
        
        // 初始化运行时状态
        self.isRunning = false
        self.runningProcessPID = nil
        self.uncommittedFileCount = 0
        self.terminalOutput = ""
        self.transitionState = .idle
    }

    /// 显式非隔离编码
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(type, forKey: .type)
        try container.encode(currentBranch, forKey: .currentBranch)
        try container.encode(startCommand, forKey: .startCommand)
        try container.encode(buildCommand, forKey: .buildCommand)
        try container.encode(cleanCommand, forKey: .cleanCommand)
        try container.encode(installCommand, forKey: .installCommand)
        try container.encode(stopCommand, forKey: .stopCommand)
        try container.encode(discardChangesCommand, forKey: .discardChangesCommand)
        try container.encodeIfPresent(commandProfileName, forKey: .commandProfileName)
        try container.encode(installStrategy, forKey: .installStrategy)
        try container.encodeIfPresent(commandConfigId, forKey: .commandConfigId)
        try container.encode(addedDate, forKey: .addedDate)
    }
}

extension Project {
    init(
        name: String,
        path: String,
        type: ProjectType,
        commandConfigId: UUID?,
        commandConfig: CommandConfig?
    ) {
        self = ProjectCommandSnapshotResolver.makeProject(
            name: name,
            path: path,
            type: type,
            commandConfigId: commandConfigId,
            legacyConfig: commandConfig
        )
    }

    func backfillingMissingCommandSnapshot(from snapshot: ProjectCommandSnapshot?) -> Project {
        guard let snapshot else { return self }
        var updated = self

        if updated.startCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.startCommand = snapshot.startCommand
        }
        if updated.buildCommand.isEmpty {
            updated.buildCommand = snapshot.buildCommand
        }
        if updated.cleanCommand.isEmpty {
            updated.cleanCommand = snapshot.cleanCommand
        }
        if updated.installCommand.isEmpty {
            updated.installCommand = snapshot.installCommand
        }
        if updated.stopCommand.isEmpty {
            updated.stopCommand = snapshot.stopCommand
        }
        if updated.discardChangesCommand.isEmpty {
            updated.discardChangesCommand = snapshot.discardChangesCommand
        }
        if updated.commandProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            updated.commandProfileName = snapshot.commandProfileName
        }

        return updated
    }
}
