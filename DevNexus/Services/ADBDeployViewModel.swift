//
//  ADBDeployViewModel.swift
//  DevNexus
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
        case .idle: return "就绪"
        case .parsingAPK: return "正在解析 APK 包名..."
        case .cleaning: return "正在强力清除旧版本..."
        case .installing: return "正在执行深度安装 (-r -d -t)..."
        case .launching: return "正在强制激活应用..."
        case .success: return "部署成功 (已校验物理更新)"
        case .failure(let msg): return "部署失败: \(msg)"
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
                self.device = ADBDevice(serial: serial, brand: "未知设备", model: "", androidVersion: "", sdkVersion: "")
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

        AppLogInfo("开始部署安卓 APK：\(apk.name)")
        terminalOutput = "[系统] 启动暴力部署模式 (对齐 adb_deploy.sh)...\n"
        
        Task {
            do {
                let serial = device.serial
                let apkPath = apk.url.path
                
                // 1. 自动探测包名
                status = .parsingAPK
                appendToTerminal("[1/5] 正在解析 APK 内部包名...\n")
                let packageName = try await detectPackageName(apkPath: apkPath)
                appendToTerminal("   识别到有效包名: \(packageName)\n")
                
                // 2. 获取安装前的时间戳
                appendToTerminal("[2/5] 正在读取当前应用物理状态...\n")
                let timeBefore = await getPackageUpdateTime(packageName: packageName, serial: serial)
                appendToTerminal("   当前最后更新时间: \(timeBefore.isEmpty ? "未安装" : timeBefore)\n")
                
                // 3. 强力卸载
                status = .cleaning
                appendToTerminal("[3/5] 正在执行强力物理卸载 (清除残留缓存)...\n")
                _ = try await ModernProcessExecutor.execute(
                    command: "adb -s \(serial) uninstall \(packageName)",
                    in: URL(fileURLWithPath: "/tmp"),
                    onOutput: { [weak self] out in Task { @MainActor in self?.terminalOutput += out } }
                )
                
                // 4. 深度安装
                status = .installing
                appendToTerminal("\n[4/5] 正在执行深度安装 (-r -d -t)...\n")
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
                    throw NSError(domain: "ADBDeploy", code: 2, userInfo: [NSLocalizedDescriptionKey: "ADB 安装阶段返回失败"])
                }
                
                // 5. 校验物理更新
                let timeAfter = await getPackageUpdateTime(packageName: packageName, serial: serial)
                if timeBefore == timeAfter && !timeAfter.isEmpty {
                    appendToTerminal("\n[严重警告] 检测到物理时间戳未改变！安装可能未生效。\n")
                    status = .failure("安装未生效，请手动确认手机弹窗")
                    return
                }
                appendToTerminal("   物理校验通过：更新时间已变更为 \(timeAfter)\n")
                
                // 6. 强制激活
                status = .launching
                appendToTerminal("[5/5] 正在通过 Monkey 强制激活应用...\n")
                let monkeyCommand = "adb -s \(serial) shell monkey -p \(packageName) -c android.intent.category.LAUNCHER 1"
                let monkeyResult = try await ModernProcessExecutor.execute(
                    command: monkeyCommand,
                    in: URL(fileURLWithPath: "/tmp"),
                    onOutput: { [weak self] out in Task { @MainActor in self?.terminalOutput += out } }
                )

                self.terminalOutput += monkeyResult.finalOutput
                appendToTerminal("   Monkey exit code: \(monkeyResult.exitCode)\n")
                guard monkeyResult.exitCode == 0 else {
                    throw NSError(domain: "ADBDeploy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Monkey 激活阶段返回失败"])
                }

                status = .success
                
                AppLogSuccess("安卓 APK 部署成功：\(apk.name)")
                
            } catch {
                AppLogError("安卓 APK 部署失败：\(error.localizedDescription)")
                status = .failure(error.localizedDescription)
                appendToTerminal("\n[严重错误] \(error.localizedDescription)\n")
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
                NSLocalizedDescriptionKey: "未找到可用的 aapt2/aapt，或无法从 APK 解析包名。请安装 Android SDK Build Tools。"
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
