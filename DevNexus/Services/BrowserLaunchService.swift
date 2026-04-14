//
//  BrowserLaunchService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation

/// 浏览器启动服务
/// 使用 @MainActor 确保字典访问的线程安全
@MainActor
class BrowserLaunchService {
    // 存储监控任务，用于在服务销毁时取消
    private var monitoringTasks: [Int32: Task<Void, Never>] = [:]

    // 获取实例目录（和 dev_chrome_launcher.sh 一样）
    nonisolated private func getInstancesDir() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let instancesDir = homeDir.appendingPathComponent(".devnexus-browsers").path

        // 确保目录存在
        try? FileManager.default.createDirectory(atPath: instancesDir, withIntermediateDirectories: true, attributes: nil)

        return instancesDir
    }

    // 启动浏览器实例
    func launchBrowser(
        browserPath: String,
        url: String,
        debugPort: Int
    ) async -> Result<Int32, Error> {
        // 检查是否是 Safari
        let isSafari = browserPath.contains("Safari.app")

        if isSafari {
            // Safari 使用 open 命令启动，不支持 Chrome 的调试参数
            return await launchSafari(url: url)
        } else {
            // Chrome/Chromium 使用调试模式启动
            return await launchChromiumBrowser(browserPath: browserPath, url: url, debugPort: debugPort)
        }
    }

    // 启动 Safari（简单模式，不支持调试）
    private func launchSafari(url: String) async -> Result<Int32, Error> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Safari", url]

        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            task.standardOutput = devNull
            task.standardError = devNull
        }

        do {
            try task.run()
            let pid = task.processIdentifier

            // Safari 不保存实例信息，因为：
            // 1. Safari 不支持调试端口，无法通过端口关联
            // 2. Safari 可能已经在运行，无法准确获取新打开的标签页的 PID
            // 3. 用户可以手动关闭 Safari 标签页

            return .success(pid)
        } catch {
            return .failure(error)
        }
    }

    // 启动 Chromium 系浏览器（支持调试）
    private func launchChromiumBrowser(
        browserPath: String,
        url: String,
        debugPort: Int
    ) async -> Result<Int32, Error> {
        // 使用 /tmp 目录（和 chrome-devtools MCP 一样）
        let timestamp = Int(Date().timeIntervalSince1970)
        let profileDir = "/tmp/devnexus-browser-\(timestamp)"
        let instanceName = "browser-\(timestamp)"

        // 创建临时目录
        do {
            try FileManager.default.createDirectory(atPath: profileDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return .failure(error)
        }

        // 构建启动参数（确保独立进程）
        let arguments = [
            "--remote-debugging-port=\(debugPort)",
            "--user-data-dir=\(profileDir)",
            "--no-first-run",
            "--no-default-browser-check",
            "--new-window",  // 强制新窗口
            "--disable-features=ProcessPerSiteUpToMainFrameThreshold",  // 确保独立进程
            url
        ]

        let task = Process()
        task.executableURL = URL(fileURLWithPath: browserPath)
        task.arguments = arguments

        // 将输出重定向到 /dev/null，避免管道缓冲区满导致进程阻塞
        // 注意：不能用 FileHandle.nullDevice，它内部 fd 是 -1，
        // Process.run() 对它做 dup2 时会抛 EBADF (errno 9 - Bad file descriptor)
        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            task.standardOutput = devNull
            task.standardError = devNull
        }

        do {
            try task.run()

            // 异步等待确保启动成功
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

            if task.isRunning {
                let pid = task.processIdentifier

                // 保存实例信息（和 dev_chrome_launcher.sh 一样）
                saveInstanceInfo(
                    instanceName: instanceName,
                    pid: pid,
                    url: url,
                    debugPort: debugPort,
                    profileDir: profileDir,
                    browserPath: browserPath
                )

                // 启动监控进程（后台监控，自动清理）
                startMonitoring(pid: pid, instanceName: instanceName, profileDir: profileDir)

                return .success(pid)
            } else {
                return .failure(NSError(
                    domain: "BrowserLaunchService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "浏览器启动失败"]
                ))
            }
        } catch {
            return .failure(error)
        }
    }

    // 保存实例信息
    private func saveInstanceInfo(
        instanceName: String,
        pid: Int32,
        url: String,
        debugPort: Int,
        profileDir: String,
        browserPath: String
    ) {
        let instancesDir = getInstancesDir()

        // 保存 PID 文件
        let pidFile = "\(instancesDir)/\(instanceName).pid"
        try? "\(pid)".write(toFile: pidFile, atomically: true, encoding: .utf8)

        // 保存配置文件
        let configFile = "\(instancesDir)/\(instanceName).config"
        let config = """
        INSTANCE_URL="\(url)"
        INSTANCE_DEBUG_PORT="\(debugPort)"
        INSTANCE_PROFILE_DIR="\(profileDir)"
        INSTANCE_BROWSER_PATH="\(browserPath)"
        INSTANCE_NAME="\(instanceName)"
        """
        try? config.write(toFile: configFile, atomically: true, encoding: .utf8)
    }

    // 启动监控进程（和 dev_chrome_launcher.sh 的 monitor_chrome 一样）
    private func startMonitoring(pid: Int32, instanceName: String, profileDir: String) {
        // 取消之前的监控任务（如果存在）
        monitoringTasks[pid]?.cancel()

        // 创建新的监控任务
        let task = Task { [weak self] in
            // 持续检查进程是否还在运行
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // 检查进程是否还存在
                let checkTask = Process()
                checkTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                checkTask.arguments = ["-0", "\(pid)"]
                checkTask.standardOutput = Pipe()
                checkTask.standardError = Pipe()

                do {
                    let terminationStatus = try await ProcessUtils.runAndWaitForTermination(checkTask)

                    // 如果进程不存在了，清理文件
                    if terminationStatus != 0 {
                        self?.cleanupInstance(instanceName: instanceName, profileDir: profileDir)
                        self?.monitoringTasks.removeValue(forKey: pid)
                        break
                    }
                } catch {
                    // 出错也清理
                    self?.cleanupInstance(instanceName: instanceName, profileDir: profileDir)
                    self?.monitoringTasks.removeValue(forKey: pid)
                    break
                }
            }
        }

        // 保存任务引用
        monitoringTasks[pid] = task
    }

    // 取消所有监控任务
    func cancelAllMonitoring() {
        for (_, task) in monitoringTasks {
            task.cancel()
        }
        monitoringTasks.removeAll()
    }

    // 清理实例文件
    nonisolated private func cleanupInstance(instanceName: String, profileDir: String) {
        let instancesDir = getInstancesDir()

        // 删除 PID 和配置文件
        try? FileManager.default.removeItem(atPath: "\(instancesDir)/\(instanceName).pid")
        try? FileManager.default.removeItem(atPath: "\(instancesDir)/\(instanceName).config")

        // 删除临时数据目录
        try? FileManager.default.removeItem(atPath: profileDir)
    }

    // 验证 URL 格式
    func validateURL(_ urlString: String) -> Bool {
        // 如果是 localhost 或 IP 地址，自动添加 http://
        var finalURL = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            finalURL = "http://\(urlString)"
        }

        return URL(string: finalURL) != nil
    }

    // 标准化 URL
    func normalizeURL(_ urlString: String) -> String {
        var finalURL = urlString.trimmingCharacters(in: .whitespaces)

        // 如果没有协议，添加 http://
        if !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
            finalURL = "http://\(finalURL)"
        }

        return finalURL
    }

    /// 检查端口是否可用
    /// - Parameter port: 要检查的端口号
    /// - Returns: true 表示端口可用，false 表示端口被占用，nil 表示无法确定
    /// - Note: 这是一个 nonisolated 方法，可以在后台线程安全调用
    nonisolated func isPortAvailable(_ port: Int) -> Bool? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-i", ":\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "BrowserLaunchService")

            guard terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // 如果有输出，说明端口被占用；输出为空说明端口可用
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            // 如果命令执行失败，返回 nil 表示无法确定
            return nil
        }
    }

    /// 查找可用端口
    /// - Parameter startingFrom: 起始端口号
    /// - Returns: 可用的端口号，如果没有找到返回 nil
    /// - Note: 这是一个 nonisolated 方法，可以在后台线程安全调用
    nonisolated func findAvailablePort(startingFrom: Int = 9222) -> Int? {
        var port = startingFrom
        let maxPort = 65535

        while port < maxPort {
            if let available = isPortAvailable(port) {
                if available {
                    return port
                }
            }
            // 如果无法检查端口或端口不可用，尝试下一个
            port += 1
        }

        // 如果达到最大端口仍未找到可用端口，返回 nil
        return nil
    }
}
