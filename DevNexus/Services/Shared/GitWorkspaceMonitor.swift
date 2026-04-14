//
//  GitWorkspaceMonitor.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/03/10.
//

import Foundation
import CoreServices

/// Git 工作区监听器 (符合 C API 桥接规范且解决隔离冲突的最终版)
/// 
/// 依据：
/// 1. FSEvents 回调在后台线程运行，必须调用 nonisolated 方法以避开运行时隔离检查。
/// 2. 使用 NSLock 保护所有并发访问的 var。
final class GitWorkspaceMonitor: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    
    private let debounceThreshold: TimeInterval = 1.0 // 1000ms
    nonisolated(unsafe) private var debounceWorkItem: DispatchWorkItem?
    
    private let onNotify: @Sendable () -> Void
    private let workspacePath: String
    private let appSupportExcludePath: String

    init(path: String, onNotify: @escaping @Sendable () -> Void) {
        self.workspacePath = path
        self.onNotify = onNotify
        
        let bundleID = Bundle.main.bundleIdentifier ?? "studio.slippindylan.DevNexus"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleID).path ?? ""
        self.appSupportExcludePath = appSupport
    }

    /// 外部启动方法
    func start() {
        lock.lock()
        defer { lock.unlock() }
        
        guard stream == nil else { return }
        setupStream()
    }

    private func setupStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [workspacePath] as CFArray
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer

        if let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            GitWorkspaceMonitor.eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(flags)
        ) {
            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .background))
            FSEventStreamStart(stream)
        }
    }

    // MARK: - @convention(c) 静态回调
    private static let eventCallback: FSEventStreamCallback = { (streamRef, clientInfo, numEvents, eventPaths, eventFlags, eventIds) in
        guard let clientInfo = clientInfo else { return }
        let monitor = Unmanaged<GitWorkspaceMonitor>.fromOpaque(clientInfo).takeUnretainedValue()
        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
        
        // 进入 nonisolated 实例方法，安全跨越隔离边界
        monitor.processEvents(paths: paths)
    }

    /// MARK: - 核心修正：显式标记为 nonisolated 以防止 Swift 运行时进行隔离断言
    nonisolated private func processEvents(paths: [String]) {
        let excludePath = self.appSupportExcludePath
        
        let shouldTrigger = paths.contains { path in
            if !excludePath.isEmpty && path.hasPrefix(excludePath) {
                return false
            }
            
            let ignoredKeywords = ["/node_modules/", "/dist/", "/.DS_Store", "/.git/objects/", "/.git/hooks/"]
            for keyword in ignoredKeywords {
                if path.contains(keyword) { return false }
            }
            
            return path.hasSuffix(".git/HEAD") || 
                   path.hasSuffix(".git/index") || 
                   !path.contains("/.git/")
        }
        
        if shouldTrigger {
            triggerDebouncedNotify()
        }
    }

    /// MARK: - 核心修正：显式标记为 nonisolated
    nonisolated private func triggerDebouncedNotify() {
        lock.lock()
        defer { lock.unlock() }
        
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onNotify()
        }
        debounceWorkItem = item
        
        // 在主队列调度执行，确保最终的 UI 刷新通知处于正确环境
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceThreshold, execute: item)
    }

    nonisolated func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        if let stream = self.stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    deinit {
        stop()
    }
}
