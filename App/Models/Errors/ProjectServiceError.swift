//
//  ProjectServiceError.swift
//  Techne
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
            return AppLocalizedFormat("error.project.path_not_found", path)
        case .projectAlreadyExists(let name):
            return AppLocalizedFormat("error.project.already_exists", name)
        case .gitOperationFailed(let operation, let reason):
            return AppLocalizedFormat("error.project.git_operation_failed", operation, reason)
        case .processStartFailed(let message):
            return AppLocalizedFormat("error.project.process_start_failed", message)
        case .processStopFailed(let message):
            return AppLocalizedFormat("error.project.process_stop_failed", message)
        case .persistenceFailed(let message):
            return AppLocalizedFormat("error.project.persistence_failed", message)
        case .invalidConfiguration(let message):
            return AppLocalizedFormat("error.project.invalid_configuration", message)
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pathNotFound:
            return AppLocalized("error.project.path_not_found.recovery")
        case .projectAlreadyExists:
            return AppLocalized("error.project.already_exists.recovery")
        case .gitOperationFailed:
            return AppLocalized("error.project.git_operation_failed.recovery")
        case .processStartFailed:
            return AppLocalized("error.project.process_start_failed.recovery")
        case .processStopFailed:
            return AppLocalized("error.project.process_stop_failed.recovery")
        case .persistenceFailed:
            return AppLocalized("error.project.persistence_failed.recovery")
        case .invalidConfiguration:
            return AppLocalized("error.project.invalid_configuration.recovery")
        }
    }
}
