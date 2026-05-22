//
//  CommandConfigService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation
import Observation

/// 命令配置管理服务
@MainActor
@Observable
final class CommandConfigService {
    var configs: [CommandConfig] = []

    private let persistenceService: PersistenceService<CommandConfig>

    init(
        persistenceService: PersistenceService<CommandConfig> = PersistenceService(filename: "commandconfigs.json")
    ) {
        self.persistenceService = persistenceService
        loadConfigs()
    }

    // MARK: - Config Management

    func addConfig(_ config: CommandConfig) -> Result<CommandConfig, ProjectServiceError> {
        // 验证配置
        if let error = validateConfig(config) {
            return .failure(error)
        }

        // 检查名称是否已存在
        if configs.contains(where: { $0.name == config.name }) {
            return .failure(.invalidConfiguration("配置名称已存在: \(config.name)"))
        }

        configs.append(config)
        saveConfigs()
        return .success(config)
    }

    func updateConfig(_ config: CommandConfig) -> Result<Void, ProjectServiceError> {
        // 验证配置
        if let error = validateConfig(config) {
            return .failure(error)
        }

        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            saveConfigs()
            return .success(())
        }

        return .failure(.invalidConfiguration("配置不存在"))
    }

    // MARK: - Validation

    /// 验证配置是否有效
    /// - Parameter config: 要验证的配置
    /// - Returns: 如果配置无效，返回错误；否则返回 nil
    private func validateConfig(_ config: CommandConfig) -> ProjectServiceError? {
        // 验证名称
        if config.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return .invalidConfiguration("配置名称不能为空")
        }

        // 验证启动命令
        if config.startCommand.trimmingCharacters(in: .whitespaces).isEmpty {
            return .invalidConfiguration("启动命令不能为空")
        }

        // 验证所有命令字段的安全性
        let allCommands = [
            config.startCommand,
            config.buildCommand,
            config.cleanCommand,
            config.discardChangesCommand,
            config.installCommand,
            config.stopCommand
        ]

        // 危险命令模式
        let dangerousPatterns = [
            "rm -rf /",
            "sudo rm",
            ":(){ :|:& };:",  // Fork bomb
            "mkfs",
            "dd if=/dev/zero",
            ">/dev/",
            "curl.*|.*sh",  // 下载并执行脚本
            "wget.*|.*sh"
        ]

        for command in allCommands {
            guard !command.isEmpty else { continue }

            for pattern in dangerousPatterns {
                if command.contains(pattern) {
                    return .invalidConfiguration("命令包含危险操作: \(pattern)")
                }
            }
        }

        return nil
    }

    func removeConfig(_ config: CommandConfig) {
        configs.removeAll { $0.id == config.id }
        saveConfigs()
    }

    func getConfig(by id: UUID) -> CommandConfig? {
        configs.first { $0.id == id }
    }

    func replaceConfigsForImport(_ configs: [CommandConfig]) {
        self.configs = configs
        saveConfigs()
    }

    func mergeImportedConfigs(_ configs: [CommandConfig]) {
        self.configs = BackupService.mergeConfigs(existing: self.configs, incoming: configs)
        saveConfigs()
    }

    func applyPersistenceMigration(_ configs: [CommandConfig]) {
        guard self.configs != configs else {
            return
        }

        self.configs = configs
        saveConfigs()
    }

    // MARK: - Persistence

    private func loadConfigs() {
        configs = persistenceService.load()
    }

    private func saveConfigs() {
        _ = persistenceService.save(configs)
    }
}
