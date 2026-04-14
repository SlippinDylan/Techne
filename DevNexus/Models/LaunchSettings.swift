//
//  LaunchSettings.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/03/10.
//

import SwiftUI
import ServiceManagement
import Observation

/// 登录项设置 (Phase 4 重构版)
/// 直接绑定 SMAppService.mainApp.status，实现 Single Source of Truth
@MainActor
@Observable
final class LaunchSettings {
    static let shared = LaunchSettings()
    
    var isLaunchAtLoginEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                LogService.shared.error("设置登录项失败：\(error.localizedDescription)", category: "系统")
            }
        }
    }
    
    private init() {}
}
