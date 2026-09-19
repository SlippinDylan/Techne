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

        logService.info(AppLocalized("log.browser.scan_started"), category: AppLocalized("log.category.browser_detection"))
        isLoading = true

        let instanceStore = self.instanceStore
        Task.detached { [weak self] in
            do {
                let foundInstances = try instanceStore.loadTrackedInstances().map { $0.makeChromeInstance() }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.instances = foundInstances
                    self.isLoading = false
                    self.logService.success(AppLocalizedFormat("log.browser.scan_completed", Int64(foundInstances.count)), category: AppLocalized("log.category.browser_detection"))
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    self.logService.error(AppLocalizedFormat("log.browser.scan_failed", error.localizedDescription), category: AppLocalized("log.category.browser_detection"))
                }
            }
        }
    }

    // MARK: - Instance Control

    /// 关闭单个实例
    func killInstance(_ instance: ChromeInstance) -> Bool {
        logService.info(AppLocalizedFormat("log.browser.closing", instance.displayName, instance.id), category: AppLocalized("log.category.browser"))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-TERM", "\(instance.id)"]

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "ChromeDetectionService")

            let success = terminationStatus == 0

            if success {
                logService.success(AppLocalizedFormat("log.browser.closed", instance.displayName), category: AppLocalized("log.category.browser"))
                refreshUntilInstanceDisappears(pid: instance.id)
            } else {
                logService.error(AppLocalizedFormat("log.browser.close_failed", instance.displayName), category: AppLocalized("log.category.browser"))
            }

            return success
        } catch {
            logService.error(AppLocalizedFormat("log.browser.close_error", error.localizedDescription), category: AppLocalized("log.category.browser"))
            return false
        }
    }

    /// 关闭所有实例
    func killAllInstances() {
        logService.info(AppLocalizedFormat("log.browser.closing_all", Int64(instances.count)), category: AppLocalized("log.category.browser"))

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
