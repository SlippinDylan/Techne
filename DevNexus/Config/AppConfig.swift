//
//  AppConfig.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 应用配置常量
/// 标记为 nonisolated 以支持跨隔离域访问
nonisolated enum AppConfig {
    /// UI 相关配置
    enum UI {
        /// 图标大小
        static let iconSize: CGFloat = 24

        /// 字体大小
        static let smallFontSize: CGFloat = 11
        static let mediumFontSize: CGFloat = 13
        static let largeFontSize: CGFloat = 15
        static let titleFontSize: CGFloat = 16

        /// 间距
        static let smallSpacing: CGFloat = 4
        static let mediumSpacing: CGFloat = 8
        static let largeSpacing: CGFloat = 12
        static let extraLargeSpacing: CGFloat = 16

        /// 内边距
        static let smallPadding: CGFloat = 8
        static let mediumPadding: CGFloat = 12
        static let largePadding: CGFloat = 16
        static let extraLargePadding: CGFloat = 20

        /// 圆角
        static let smallCornerRadius: CGFloat = 4
        static let mediumCornerRadius: CGFloat = 6
        static let largeCornerRadius: CGFloat = 8

        /// 容器大小
        static let iconContainerSize: CGFloat = 48
        static let smallIconSize: CGFloat = 20
        static let mediumIconSize: CGFloat = 32

        /// 刷新延迟
        static let refreshDelay: TimeInterval = 0.5
    }

    /// 进程相关配置
    enum Process {
        /// 启动延迟（秒）
        static let startupDelay: UInt32 = 2

        /// 终端输出限制（字符数）
        static let terminalOutputLimit = 50_000

        /// 进程检测关键词（包含所有支持的运行时）
        static let processKeywords = ["node", "esbuild", "vite", "webpack", "bun", "deno"]
    }

    /// Git 相关配置
    enum Git {
        /// 默认分支
        static let defaultBranch = "main"

        /// 缓存清理命令
        static let cacheCleanCommand = "rm -rf dist node_modules/.cache"
    }

    /// 服务器检测配置
    enum ServerDetection {
        /// 端口范围
        static let portRange = 3000...9999

        /// 排除的端口
        static let excludedPorts: Set<Int> = []
    }

    /// 开发服务器配置
    enum DevServer {
        /// 开发进程关键词
        static let devProcesses = ["node", "bun", "deno"]
    }

    /// 浏览器相关配置
    enum Browser {
        /// 默认调试端口起始值
        static let defaultDebugPort = 9222

        /// 最大端口号
        static let maxPort = 65535
    }

    /// 延迟配置
    enum Delays {
        /// 服务器启动后的刷新延迟（秒）
        static let serverStartRefresh: TimeInterval = 2.0

        /// 服务器停止后的刷新延迟（秒）
        static let serverStopRefresh: TimeInterval = 2.0

        /// 缓存清理延迟（秒）
        static let cacheCleanup: TimeInterval = 1.0
    }

    /// 持久化配置
    enum Persistence {
        /// 数据保存防抖延迟（秒）
        static let saveDebounce: TimeInterval = 0.5
    }
}
