//
//  ADBDeployViewModel.swift
//  Techne
//
//  Created by SlippinDylan on 2026/03/10.
//

import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// 部署状态
enum DeployStatus: Equatable {
    case idle
    case parsingAPK      // 正在解析 APK 信息
    case cleaning        // 正在强力卸载旧版
    case installing      // 正在执行深度安装
    case launching       // 正在强制激活
    case success
    case failure(String)
    
    var description: String {
        switch self {
        case .idle: return AppLocalized("deploy.status.ready")
        case .parsingAPK: return AppLocalized("deploy.status.parsing_apk")
        case .cleaning: return AppLocalized("deploy.status.cleaning")
        case .installing: return AppLocalized("deploy.status.installing")
        case .launching: return AppLocalized("deploy.status.launching")
        case .success: return AppLocalized("deploy.status.success")
        case .failure(let msg): return AppLocalizedFormat("deploy.status.failure", msg)
        }
    }
}

/// 设备信息模型
struct ADBDevice: Sendable {
    let serial: String
    let brand: String
    let model: String
    let androidVersion: String
    let sdkVersion: String
    
    var isConnected: Bool { !serial.isEmpty }
}

/// APK 文件模型
struct APKFile: Sendable {
    let url: URL
    let name: String
    let size: Int64
    let modificationDate: Date
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

@MainActor
@Observable
final class ADBDeployViewModel {
    // MARK: - State
    
    var device: ADBDevice?
    var selectedAPK: APKFile?
    var status: DeployStatus = .idle
    var terminalOutput: String = ""
    var isPolling: Bool = false
    
    private var currentSuccessFlag: Bool = false
    private var pollingTask: Task<Void, Never>?
    
    init() {
        startPolling()
    }
    
    // MARK: - Device Polling
    
    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        
        pollingTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                if let self = self {
                    await self.updateDeviceInfo()
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        isPolling = false
    }
    
    private func updateDeviceInfo() async {
        do {
            let devicesOutput = try await self.executeADBCommand("adb devices")
            let serial = parseSerial(from: devicesOutput)
            
            if serial.isEmpty {
                self.device = nil
                return
            }
            
            let command = "adb -s \(serial) shell \"getprop ro.product.brand; getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk\""
            let infoOutput = try await self.executeADBCommand(command)
            
            let parts = infoOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if parts.count >= 4 {
                self.device = ADBDevice(
                    serial: serial,
                    brand: parts[0].trimmingCharacters(in: .whitespaces),
                    model: parts[1].trimmingCharacters(in: .whitespaces),
                    androidVersion: parts[2].trimmingCharacters(in: .whitespaces),
                    sdkVersion: parts[3].trimmingCharacters(in: .whitespaces)
                )
            } else {
                self.device = ADBDevice(serial: serial, brand: AppLocalized("deploy.device.unknown"), model: "", androidVersion: "", sdkVersion: "")
            }
        } catch {
            self.device = nil
        }
    }
    
    // MARK: - Actions
    
    func selectAPK() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.init(filenameExtension: "apk")!]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        
        if panel.runModal() == .OK, let url = panel.url {
            selectAPKFile(at: url)
        }
    }

    func selectAPKFile(at url: URL) {
        guard url.pathExtension.lowercased() == "apk" else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let date = (attrs?[.modificationDate] as? Date) ?? Date()

        selectedAPK = APKFile(url: url, name: url.lastPathComponent, size: size, modificationDate: date)
    }
    
    /// 执行强力部署流 (真·安装)
    func deploy() {
        guard let apk = selectedAPK, let device = device else { return }

        AppLogInfo(AppLocalizedFormat("log.adb.deployment_started", apk.name))
        terminalOutput = AppLocalized("terminal.adb.deployment_started")
        
        Task {
            do {
                let serial = device.serial
                let apkPath = apk.url.path
                
                // 1. 自动探测包名
                status = .parsingAPK
                appendToTerminal(AppLocalized("terminal.adb.parsing_package_name"))
                let packageName = try await detectPackageName(apkPath: apkPath)
                appendToTerminal(AppLocalizedFormat("terminal.adb.package_name_found", packageName))
                
                // 2. 获取安装前的时间戳
                appendToTerminal(AppLocalized("terminal.adb.reading_package_state"))
                let timeBefore = await getPackageUpdateTime(packageName: packageName, serial: serial)
                appendToTerminal(AppLocalizedFormat("terminal.adb.current_update_time", timeBefore.isEmpty ? AppLocalized("deploy.not_installed") : timeBefore))
                
                // 3. 强力卸载
                status = .cleaning
                appendToTerminal(AppLocalized("terminal.adb.uninstalling"))
                _ = try await ModernProcessExecutor.execute(
                    command: "adb -s \(serial) uninstall \(packageName)",
                    in: URL(fileURLWithPath: "/tmp"),
                    onOutput: { [weak self] out in Task { @MainActor in self?.terminalOutput += out } }
                )
                
                // 4. 深度安装
                status = .installing
                appendToTerminal(AppLocalized("terminal.adb.installing"))
                self.currentSuccessFlag = false
                let result = try await ModernProcessExecutor.execute(
                    command: "adb -s \(serial) install -r -d -t \"\(apkPath)\"",
                    in: URL(fileURLWithPath: "/tmp"),
                    onOutput: { [weak self] out in
                        Task { @MainActor in 
                            self?.terminalOutput += out
                            if out.contains("Success") { self?.currentSuccessFlag = true }
                        }
                    }
                )
                
                // MARK: - 依据 Flush 修正逻辑：合并残留输出
                if result.finalOutput.contains("Success") { self.currentSuccessFlag = true }
                self.terminalOutput += result.finalOutput
                
                guard self.currentSuccessFlag && result.exitCode == 0 else {
                    throw NSError(domain: "ADBDeploy", code: 2, userInfo: [NSLocalizedDescriptionKey: AppLocalized("error.adb.install_failed")])
                }
                
                // 5. 校验物理更新
                let timeAfter = await getPackageUpdateTime(packageName: packageName, serial: serial)
                if timeBefore == timeAfter && !timeAfter.isEmpty {
                    appendToTerminal(AppLocalized("terminal.adb.timestamp_unchanged"))
                    status = .failure(AppLocalized("error.adb.install_not_applied"))
                    return
                }
                appendToTerminal(AppLocalizedFormat("terminal.adb.install_verified", timeAfter))
                
                // 6. 强制激活
                status = .launching
                appendToTerminal(AppLocalized("terminal.adb.launching"))
                let monkeyCommand = "adb -s \(serial) shell monkey -p \(packageName) -c android.intent.category.LAUNCHER 1"
                let monkeyResult = try await ModernProcessExecutor.execute(
                    command: monkeyCommand,
                    in: URL(fileURLWithPath: "/tmp"),
                    onOutput: { [weak self] out in Task { @MainActor in self?.terminalOutput += out } }
                )

                self.terminalOutput += monkeyResult.finalOutput
                appendToTerminal(AppLocalizedFormat("terminal.adb.monkey_exit_code", monkeyResult.exitCode))
                guard monkeyResult.exitCode == 0 else {
                    throw NSError(domain: "ADBDeploy", code: 3, userInfo: [NSLocalizedDescriptionKey: AppLocalized("error.adb.monkey_failed")])
                }

                status = .success
                
                AppLogSuccess(AppLocalizedFormat("log.adb.deployment_succeeded", apk.name))
                
            } catch {
                AppLogError(AppLocalizedFormat("log.adb.deployment_failed", error.localizedDescription))
                status = .failure(error.localizedDescription)
                appendToTerminal(AppLocalizedFormat("terminal.adb.fatal_error", error.localizedDescription))
            }
        }
    }
    
    func clearTerminal() {
        terminalOutput = ""
    }
    
    // MARK: - Helper Methods
    
    private func appendToTerminal(_ text: String) {
        terminalOutput += text
    }
    
    private func detectPackageName(apkPath: String) async throws -> String {
        if let aapt2Path = try await findBuildTool(named: "aapt2") {
            let command = "\"\(aapt2Path)\" dump packagename \"\(apkPath)\""
            let packageName = sanitizePackageName(try await executeADBCommand(command))
            if !packageName.isEmpty {
                return packageName
            }
        }

        if let aaptPath = try await findBuildTool(named: "aapt") {
            let command = "\"\(aaptPath)\" dump badging \"\(apkPath)\" | grep package: | awk '{print $2}' | sed \"s/name='//g\" | sed \"s/'//g\""
            let packageName = sanitizePackageName(try await executeADBCommand(command))
            if !packageName.isEmpty {
                return packageName
            }
        }

        throw NSError(
            domain: "ADBDeploy",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: AppLocalized("error.adb.build_tools_not_found")
            ]
        )
    }
    
    private func sanitizePackageName(_ raw: String) -> String {
        if raw.contains("command not found") || raw.contains("/bin/bash") || raw.isEmpty {
            return ""
        }
        let filtered = raw.filter { "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.".contains($0) }
        return filtered
    }
    
    private func getPackageUpdateTime(packageName: String, serial: String) async -> String {
        let command = "adb -s \(serial) shell dumpsys package \(packageName) | grep lastUpdateTime"
        let output = (try? await executeADBCommand(command)) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findBuildTool(named toolName: String) async throws -> String? {
        let command = "command -v \(toolName) || find ~/Library/Android/sdk/build-tools -name \(toolName) 2>/dev/null | head -n 1"
        let output = try await executeADBCommand(command)

        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.contains("not found") })
    }
    
    private func executeADBCommand(_ command: String) async throws -> String {
        // MARK: - 核心修正：内部创建局部 OutputBuffer 彻底解决竞态风险
        let buffer = OutputBuffer()
        
        let result = try await ModernProcessExecutor.execute(command: command, in: URL(fileURLWithPath: "/tmp")) { output in
            // 直接追加到非隔离 buffer，不碰主线程
            buffer.append(output)
        }
        
        // 合并最后冲刷出的数据并返回完整内容，无需任何 sleep
        buffer.append(result.finalOutput)
        return buffer.get()
    }
    
    private func parseSerial(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("\tdevice") {
                return line.components(separatedBy: "\t")[0].trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
