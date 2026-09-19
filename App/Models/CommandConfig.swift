//
//  CommandConfig.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 项目类型
enum ProjectType: String, Codable, CaseIterable, Sendable {
    case devServer = "开发服务与实例"
    case miniApp = "微信小程序构建"

    var displayName: String {
        switch self {
        case .devServer:
            return AppLocalized("project_type.development_services")
        case .miniApp:
            return AppLocalized("project_type.mini_program_build")
        }
    }
}

/// 命令配置模板
/// 显式标记为 Sendable 并自定义 Codable 实现以解除隐式 MainActor 隔离
struct CommandConfig: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String                    // 配置名称（必填）
    var projectType: ProjectType        // 项目类型
    var startCommand: String            // 启动命令
    var buildCommand: String            // 编译命令
    var cleanCommand: String            // 清理缓存命令
    var discardChangesCommand: String   // 丢弃更改命令
    var installCommand: String          // 安装依赖命令
    var stopCommand: String             // 停止命令

    init(
        id: UUID = UUID(),
        name: String,
        projectType: ProjectType,
        startCommand: String = "",
        buildCommand: String = "",
        cleanCommand: String = "",
        discardChangesCommand: String = "",
        installCommand: String = "",
        stopCommand: String = ""
    ) {
        self.id = id
        self.name = name
        self.projectType = projectType
        self.startCommand = startCommand
        self.buildCommand = buildCommand
        self.cleanCommand = cleanCommand
        self.discardChangesCommand = discardChangesCommand
        self.installCommand = installCommand
        self.stopCommand = stopCommand
    }

    static func == (lhs: CommandConfig, rhs: CommandConfig) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, projectType, startCommand, buildCommand, cleanCommand, discardChangesCommand, installCommand, stopCommand
    }

    /// 显式非隔离初始化
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.projectType = try container.decode(ProjectType.self, forKey: .projectType)
        self.startCommand = try container.decode(String.self, forKey: .startCommand)
        self.buildCommand = try container.decode(String.self, forKey: .buildCommand)
        self.cleanCommand = try container.decode(String.self, forKey: .cleanCommand)
        self.discardChangesCommand = try container.decode(String.self, forKey: .discardChangesCommand)
        self.installCommand = try container.decode(String.self, forKey: .installCommand)
        self.stopCommand = try container.decode(String.self, forKey: .stopCommand)
    }

    /// 显式非隔离编码
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(projectType, forKey: .projectType)
        try container.encode(startCommand, forKey: .startCommand)
        try container.encode(buildCommand, forKey: .buildCommand)
        try container.encode(cleanCommand, forKey: .cleanCommand)
        try container.encode(discardChangesCommand, forKey: .discardChangesCommand)
        try container.encode(installCommand, forKey: .installCommand)
        try container.encode(stopCommand, forKey: .stopCommand)
    }

    // MARK: - 预设配置

    static let vitePnpm = CommandConfig(
        name: "Vite + pnpm",
        projectType: .devServer,
        startCommand: "pnpm dev",
        buildCommand: "pnpm build",
        cleanCommand: "rm -rf dist node_modules/.cache",
        discardChangesCommand: "git reset --hard && git clean -fd",
        installCommand: "pnpm install"
    )

    static let miniAppNpm = CommandConfig(
        name: "微信小程序 + npm",
        projectType: .miniApp,
        startCommand: "npm run dev:mp-weixin",
        buildCommand: "npm run build:mp-weixin",
        cleanCommand: "rm -rf dist",
        discardChangesCommand: "git reset --hard && git clean -fd",
        installCommand: "npm install"
    )

    static let miniAppPnpm = CommandConfig(
        name: "微信小程序 + pnpm",
        projectType: .miniApp,
        startCommand: "pnpm dev:mp-weixin",
        buildCommand: "pnpm build:mp-weixin",
        cleanCommand: "rm -rf dist",
        discardChangesCommand: "git reset --hard && git clean -fd",
        installCommand: "pnpm install"
    )

    static let nextjsNpm = CommandConfig(
        name: "Next.js + npm",
        projectType: .devServer,
        startCommand: "npm run dev",
        buildCommand: "npm run build",
        cleanCommand: "rm -rf .next",
        discardChangesCommand: "git reset --hard && git clean -fd",
        installCommand: "npm install"
    )

    static var defaultConfigs: [CommandConfig] {
        [
            .vitePnpm,
            .miniAppNpm,
            .miniAppPnpm,
            .nextjsNpm
        ]
    }
}
