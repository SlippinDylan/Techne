//
//  ProjectServiceError.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 项目服务错误类型
enum ProjectServiceError: LocalizedError {
    case pathNotFound(String)
    case projectAlreadyExists(String)
    case gitOperationFailed(operation: String, reason: String)
    case processStartFailed(String)
    case processStopFailed(String)
    case persistenceFailed(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .pathNotFound(let path):
            return "路径不存在: \(path)"
        case .projectAlreadyExists(let name):
            return "项目已存在: \(name)"
        case .gitOperationFailed(let operation, let reason):
            return "Git 操作失败 (\(operation)): \(reason)"
        case .processStartFailed(let message):
            return "进程启动失败: \(message)"
        case .processStopFailed(let message):
            return "进程停止失败: \(message)"
        case .persistenceFailed(let message):
            return "持久化失败: \(message)"
        case .invalidConfiguration(let message):
            return "配置无效: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pathNotFound:
            return "请检查路径是否正确，确保目录存在"
        case .projectAlreadyExists:
            return "请使用不同的项目名称或路径"
        case .gitOperationFailed:
            return "请确保项目是有效的 Git 仓库，并且没有未提交的更改"
        case .processStartFailed:
            return "请检查启动命令是否正确，确保依赖已安装"
        case .processStopFailed:
            return "请尝试手动终止进程或重启应用"
        case .persistenceFailed:
            return "请检查磁盘空间和文件权限"
        case .invalidConfiguration:
            return "请检查配置文件格式是否正确"
        }
    }
}
