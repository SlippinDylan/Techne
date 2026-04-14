//
//  DevServerDetectionService.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation
import Observation

@MainActor
@Observable
final class DevServerDetectionService {
    var servers: [DevServer] = []
    var isLoading: Bool = false

    private let logService = LogService.shared
    private var pendingDetectionTasks: [Int32: Task<Void, Never>] = [:]

    init() {
        // 初始化时不自动刷新，等待手动触发
    }

    // MARK: - Public Methods

    /// 扫描所有开发服务器
    func refresh() {
        guard !isLoading else { return }

        logService.info("开始扫描开发服务器", category: "服务器检测")
        isLoading = true

        Task.detached { [weak self] in
            let foundServers = await self?.detectAllDevServersAsync() ?? []

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.servers = foundServers
                self.isLoading = false
                if foundServers.isEmpty {
                    self.logService.warning("未找到开发服务器", category: "服务器检测")
                } else {
                    self.logService.success("扫描完成，找到 \(foundServers.count) 个开发服务器", category: "服务器检测")
                    for server in foundServers {
                        self.logService.info("  - \(server.projectName) (端口: \(server.port))", category: "服务器检测")
                    }
                }
            }
        }
    }

    func refreshUntilServerDetected(pid: Int32) {
        guard !servers.contains(where: { $0.id == pid }) else { return }
        guard pendingDetectionTasks[pid] == nil else { return }

        pendingDetectionTasks[pid] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                pendingDetectionTasks[pid] = nil
            }

            let retryDelays: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000]

            for delay in retryDelays {
                guard !Task.isCancelled else { return }
                guard !servers.contains(where: { $0.id == pid }) else { return }

                try? await Task.sleep(nanoseconds: delay)

                guard !Task.isCancelled else { return }
                guard !servers.contains(where: { $0.id == pid }) else { return }

                if !isLoading {
                    refresh()
                }

                try? await Task.sleep(nanoseconds: 350_000_000)

                guard !Task.isCancelled else { return }
                guard !servers.contains(where: { $0.id == pid }) else { return }
            }
        }
    }

    // MARK: - Private Methods

    /// 检测所有开发服务器（异步版本，在后台线程执行）
    private nonisolated func detectAllDevServersAsync() async -> [DevServer] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try await ProcessUtils.runAndWaitForTermination(task)

            guard terminationStatus == 0 else {
                return []
            }

            let data = try await pipe.fileHandleForReading.bytes.reduce(into: Data()) { $0.append($1) }
            if let output = String(data: data, encoding: .utf8) {
                return DevServerParser().parseDevServers(from: output)
            }
        } catch {
            return []
        }

        return []
    }

    // MARK: - Server Control

    /// 关闭单个服务器
    func killServer(_ server: DevServer) -> Bool {
        logService.info("关闭服务器: \(server.projectName) (PID: \(server.id))", category: "服务器")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-TERM", "\(server.id)"]

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "DevServerDetectionService")

            let success = terminationStatus == 0

            if success {
                logService.success("成功关闭服务器: \(server.projectName)", category: "服务器")
            } else {
                logService.error("关闭服务器失败: \(server.projectName)", category: "服务器")
            }

            // 等待一下再刷新
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(AppConfig.UI.refreshDelay))
                self?.refresh()
            }

            return success
        } catch {
            logService.error("关闭服务器异常: \(error.localizedDescription)", category: "服务器")
            return false
        }
    }

    /// 关闭所有服务器
    func killAllServers() {
        logService.info("关闭所有服务器 (共 \(servers.count) 个)", category: "服务器")

        for server in servers {
            _ = killServer(server)
        }
    }
}
