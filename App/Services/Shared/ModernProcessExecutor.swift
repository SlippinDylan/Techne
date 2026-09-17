//
//  ModernProcessExecutor.swift
//  Techne
//
//  Created by SlippinDylan on 2026/03/10.
//

import Foundation

/// 现代化的进程执行器 (Swift 6 并发安全)
/// 解决了线程阻塞、僵尸进程残留以及高频输出导致的 UI 队列积压问题
final actor ModernProcessExecutor: Sendable {
    
    /// 执行 Shell 命令并提供合并后的流式输出
    /// - Parameters:
    ///   - command: 待执行的脚本
    ///   - directory: 工作目录
    ///   - onOutput: 合并后的输出回调 (100ms 窗口)
    /// - Returns: (进程退出码, 最后冲刷的残留输出)
    @discardableResult
    static func execute(
        command: String,
        in directory: URL,
        onStart: (@Sendable (Int32) -> Void)? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> (exitCode: Int32, finalOutput: String) {
        let process = Process()
        let cancellationController = ProcessCancellationController()
        process.executableURL = ShellExecutionEnvironment.shellURL()
        process.arguments = ShellExecutionEnvironment.arguments(for: command)
        process.currentDirectoryURL = directory
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // MARK: - 依据 Flush Pattern：建立批处理容器并获取引用
        let ioQueue = DispatchQueue(label: "com.techne.io-batcher", qos: .userInitiated)
        let batcher = StreamBatcher(onOutput: onOutput, queue: ioQueue)
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            batcher.process(data: data)
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            batcher.process(data: data)
        }
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { p in
                    // 1. 必须先解除 readabilityHandler，否则调用 readData 会导致异常
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    
                    // 2. 同步读完残留数据
                    let remainingOut = try? outputPipe.fileHandleForReading.readToEnd()
                    let remainingErr = try? errorPipe.fileHandleForReading.readToEnd()
                    let remainingOutStr = remainingOut.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let remainingErrStr = remainingErr.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    
                    // 3. flush batcher 得到缓冲中的数据
                    let batched = batcher.flush()
                    
                    // 4. 合并作为 finalOutput
                    let finalOutput = batched + remainingOutStr + remainingErrStr
                    
                    continuation.resume(returning: (p.terminationStatus, finalOutput))
                }

                do {
                    try process.run()
                    onStart?(process.processIdentifier)
                    cancellationController.processDidStart(process)
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancellationController.requestCancellation(of: process)
        }
    }
}

private final class ProcessCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancellationRequested = false
    nonisolated(unsafe) private var escalationScheduled = false

    nonisolated func requestCancellation(of process: Process) {
        lock.lock()
        cancellationRequested = true
        let shouldSchedule = process.isRunning && escalationScheduled == false
        if shouldSchedule {
            escalationScheduled = true
        }
        lock.unlock()

        if shouldSchedule {
            scheduleInterruption(of: process)
        }
    }

    nonisolated func processDidStart(_ process: Process) {
        lock.lock()
        let shouldSchedule = cancellationRequested && escalationScheduled == false
        if shouldSchedule {
            escalationScheduled = true
        }
        lock.unlock()

        if shouldSchedule {
            scheduleInterruption(of: process)
        }
    }

    private nonisolated func scheduleInterruption(of process: Process) {
        let pid = process.processIdentifier
        process.interrupt()
        Task.detached(priority: .high) {
            try? await Task.sleep(for: .milliseconds(300))
            if process.isRunning {
                process.terminate()
            }
            try? await Task.sleep(for: .milliseconds(200))
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

/// 内部辅助类：实现输出流的 100ms 窗口批处理
private final class StreamBatcher: @unchecked Sendable {
    nonisolated(unsafe) private var pendingOutput = ""
    nonisolated(unsafe) private var workItem: DispatchWorkItem?
    private let onOutput: @Sendable (String) -> Void
    private let queue: DispatchQueue
    private let lock = NSLock()

    nonisolated init(onOutput: @escaping @Sendable (String) -> Void, queue: DispatchQueue) {
        self.onOutput = onOutput
        self.queue = queue
    }

    nonisolated func process(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        
        lock.lock()
        pendingOutput += text
        
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let output = self.pendingOutput
            self.pendingOutput = ""
            self.lock.unlock()
            
            if !output.isEmpty {
                self.onOutput(output)
            }
        }
        
        self.workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
    
    /// 依据要求：显式强制冲刷缓冲区，不等待 100ms 窗口
    nonisolated func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        workItem?.cancel()
        workItem = nil
        
        let result = pendingOutput
        pendingOutput = ""
        return result
    }
}
