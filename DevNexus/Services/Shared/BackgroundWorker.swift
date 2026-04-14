//
//  BackgroundWorker.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/03/11.
//

import Foundation

/// 线程安全的输出缓冲器
final class OutputBuffer: @unchecked Sendable {
    nonisolated(unsafe) private var _data = ""
    private let lock = NSLock()
    
    nonisolated func append(_ text: String) {
        lock.lock()
        _data += text
        lock.unlock()
    }
    
    nonisolated func get() -> String {
        lock.lock()
        let result = _data
        lock.unlock()
        return result
    }
}

/// 后台异步工作器
/// 负责处理所有耗时的 Git 和 ADB 命令，彻底隔离主线程 IO
actor BackgroundWorker {
    static let shared = BackgroundWorker()
    
    private init() {}
    
    /// 异步获取 Git 当前分支
    func getGitBranch(at path: String) async -> String {
        // 近期方案：直接读 .git/HEAD 优化分支读取速度
        let headURL = URL(fileURLWithPath: path).appendingPathComponent(".git/HEAD")
        if let headContent = try? String(contentsOf: headURL, encoding: .utf8) {
            let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ref: refs/heads/") {
                return String(trimmed.dropFirst("ref: refs/heads/".count))
            }
            // 非标准格式（如 detached HEAD）走 fallback
        }
        
        let buffer = OutputBuffer()
        let result = try? await ModernProcessExecutor.execute(command: "git branch --show-current", in: URL(fileURLWithPath: path)) { out in
            buffer.append(out)
        }
        if let finalOut = result?.finalOutput {
            buffer.append(finalOut)
        }
        return buffer.get().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 异步获取 Git 未提交文件数
    func getGitStatusCount(at path: String) async -> Int {
        let buffer = OutputBuffer()
        let result = try? await ModernProcessExecutor.execute(command: "git status --porcelain", in: URL(fileURLWithPath: path)) { out in
            buffer.append(out)
        }
        if let finalOut = result?.finalOutput {
            buffer.append(finalOut)
        }
        let lines = buffer.get().components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.count
    }
    
    /// 聚合获取项目状态
    func getProjectStatus(path: String, keywords: [String], pid: Int32?) async -> (branch: String, fileCount: Int, isRunning: Bool) {
        let branch = await getGitBranch(at: path)
        let count = await getGitStatusCount(at: path)
        
        if let pid = pid {
            // 精准模式：直接检查 PID 存活
            let isAlive = kill(pid, 0) == 0
            if !isAlive {
                // PID 已死，清理不在这里做，只返回 false
                return (branch, count, false)
            }
            return (branch, count, true)
        } else {
            return (branch, count, false)
        }
    }
}
