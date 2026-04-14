//
//  PlatformVersion.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/01/19.
//

import Foundation

/// 平台版本检测工具
///
/// 提供静态属性进行 macOS 版本检测，便于业务逻辑根据系统版本执行不同代码路径。
enum PlatformVersion {
    /// 是否为 macOS 26 (Tahoe) 或更高版本
    static var isTahoeOrLater: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// 是否为 macOS 15 (Sequoia) 或更高版本
    static var isSequoiaOrLater: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }
}
