//
//  ChromeDetectionService.swift
//  Techne
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
    private let instanceStore: BrowserInstanceStore

    init(instanceStore: BrowserInstanceStore = BrowserInstanceStore()) {
        self.instanceStore = instanceStore
    }

    // MARK: - Public Methods

    /// 刷新所有浏览器实例
    func refresh() {
        guard !isLoading else { return }

        logService.info("开始扫描浏览器实例", category: "浏览器检测")
        isLoading = true

        let instanceStore = self.instanceStore
        Task.detached { [weak self] in
            do {
                let foundInstances = try instanceStore.loadTrackedInstances().map { $0.makeChromeInstance() }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.instances = foundInstances
                    self.isLoading = false
                    self.logService.success("扫描完成，找到 \(foundInstances.count) 个浏览器实例", category: "浏览器检测")
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    self.logService.error("扫描浏览器实例失败: \(error.localizedDescription)", category: "浏览器检测")
                }
            }
        }
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
                refreshUntilInstanceDisappears(pid: instance.id)
            } else {
                logService.error("关闭浏览器实例失败: \(instance.displayName)", category: "浏览器")
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

    private func refreshUntilInstanceDisappears(pid: Int32) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            for _ in 0..<6 {
                refresh()

                if !instances.contains(where: { $0.id == pid }) {
                    return
                }

                try? await Task.sleep(for: .milliseconds(250))
            }

            refresh()
        }
    }
}
