//
//  ChromeDetectionService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/13.
//

import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class ChromeDetectionService {
    var instances: [ChromeInstance] = []
    var isLoading: Bool = false

    private let logService = LogService.shared

    init() {
        // 初始化时不自动刷新，等待手动触发
    }

    // MARK: - Public Methods

    /// 刷新所有浏览器实例
    func refresh() {
        logService.info("开始扫描浏览器实例", category: "浏览器检测")
        isLoading = true

        Task.detached { [weak self] in
            let foundInstances = await self?.loadInstancesFromFilesAsync() ?? []

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.instances = foundInstances
                self.isLoading = false
                self.logService.success("扫描完成，找到 \(foundInstances.count) 个浏览器实例", category: "浏览器检测")
            }
        }
    }

    // MARK: - Private Methods

    /// 获取实例目录（和 BrowserLaunchService 一样）
    private nonisolated func getInstancesDir() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let instancesDir = homeDir.appendingPathComponent(".devnexus-browsers").path
        return instancesDir
    }

    // 从文件中加载实例信息（异步版本，在后台线程执行）
    private nonisolated func loadInstancesFromFilesAsync() async -> [ChromeInstance] {
        var instances: [ChromeInstance] = []
        let instancesDir = getInstancesDir()

        // 检查目录是否存在
        guard FileManager.default.fileExists(atPath: instancesDir) else {
            return instances
        }

        // 获取所有 .pid 文件
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: instancesDir)
            let pidFiles = files.filter { $0.hasSuffix(".pid") }

            for pidFile in pidFiles {
                let pidFilePath = "\(instancesDir)/\(pidFile)"
                let configFilePath = pidFilePath.replacingOccurrences(of: ".pid", with: ".config")

                // 读取 PID
                guard let pidString = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
                      let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    continue
                }

                // 检查进程是否还在运行
                if !isProcessRunning(pid: pid) {
                    // 进程已结束，清理文件
                    try? FileManager.default.removeItem(atPath: pidFilePath)
                    try? FileManager.default.removeItem(atPath: configFilePath)
                    continue
                }

                // 读取配置文件
                guard let config = try? String(contentsOfFile: configFilePath, encoding: .utf8) else {
                    continue
                }

                // 解析配置
                let url = extractConfigValue(from: config, key: "INSTANCE_URL")
                let debugPortString = extractConfigValue(from: config, key: "INSTANCE_DEBUG_PORT")
                let browserPath = extractConfigValue(from: config, key: "INSTANCE_BROWSER_PATH")
                let instanceName = extractConfigValue(from: config, key: "INSTANCE_NAME")

                // 提取进程名称
                let processName = extractProcessName(from: browserPath)

                // 解析启动时间（从实例名称中提取时间戳）
                let startTime = extractStartTime(from: instanceName)

                // 创建实例
                let instance = ChromeInstance(
                    id: pid,
                    processName: processName,
                    url: url,
                    debugPort: Int(debugPortString),
                    commandLine: browserPath,
                    startTime: startTime
                )

                instances.append(instance)
            }
        } catch {
            // 错误会通过返回空数组来处理
        }

        return instances
    }

    // 检查进程是否还在运行
    private nonisolated func isProcessRunning(pid: Int32) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-0", "\(pid)"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ChromeDetectionService")
            return terminationStatus == 0
        } catch {
            return false
        }
    }

    // 从配置文件中提取值
    private nonisolated func extractConfigValue(from config: String, key: String) -> String {
        let lines = config.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("\(key)=") {
                let value = line.replacingOccurrences(of: "\(key)=", with: "")
                // 移除引号
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return ""
    }

    // 从浏览器路径中提取进程名称
    private nonisolated func extractProcessName(from browserPath: String) -> String {
        if browserPath.contains("Google Chrome") {
            return "Google Chrome"
        } else if browserPath.contains("Chromium") {
            return "Chromium"
        } else if browserPath.contains("Safari") {
            return "Safari"
        } else if browserPath.contains("Microsoft Edge") {
            return "Microsoft Edge"
        } else if browserPath.contains("Brave") {
            return "Brave Browser"
        } else if browserPath.contains("Arc") {
            return "Arc"
        }
        return "Browser"
    }

    // 从实例名称中提取启动时间
    private nonisolated func extractStartTime(from instanceName: String) -> Date {
        // 实例名称格式: browser-1234567890
        let components = instanceName.components(separatedBy: "-")
        if components.count > 1,
           let timestamp = TimeInterval(components[1]) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return Date()
    }

    // MARK: - Instance Control

    /// 关闭单个实例
    func killInstance(_ instance: ChromeInstance) -> Bool {
        logService.info("关闭浏览器实例: \(instance.displayName) (PID: \(instance.id))", category: "浏览器")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-TERM", "\(instance.id)"]

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ChromeDetectionService")

            let success = terminationStatus == 0

            if success {
                logService.success("成功关闭浏览器实例: \(instance.displayName)", category: "浏览器")
            } else {
                logService.error("关闭浏览器实例失败: \(instance.displayName)", category: "浏览器")
            }

            // 等待一下再刷新
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(AppConfig.UI.refreshDelay))
                self?.refresh()
            }

            return success
        } catch {
            logService.error("关闭浏览器实例异常: \(error.localizedDescription)", category: "浏览器")
            return false
        }
    }

    /// 关闭所有实例
    func killAllInstances() {
        logService.info("关闭所有浏览器实例 (共 \(instances.count) 个)", category: "浏览器")

        for instance in instances {
            _ = killInstance(instance)
        }
    }
}
