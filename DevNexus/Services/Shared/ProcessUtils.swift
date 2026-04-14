//
//  ProcessUtils.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/3/12.
//

import Foundation

enum ProcessUtils {
    nonisolated static func runAndWaitForTerminationSync(_ process: Process, errorDomain: String = "ProcessUtils") throws -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        let state = LockedResultBox<Int32>(errorDomain: errorDomain)

        Task {
            do {
                let terminationStatus = try await runAndWaitForTermination(process)
                state.store(.success(terminationStatus))
            } catch {
                state.store(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try state.value.get()
    }

    nonisolated static func runAndWaitForTermination(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                continuation.resume(returning: terminatedProcess.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class LockedResultBox<T>: @unchecked Sendable {
    private let errorDomain: String
    private let lock = NSLock()
    nonisolated(unsafe) private var storage: Result<T, Error>?

    nonisolated init(errorDomain: String) {
        self.errorDomain = errorDomain
    }

    nonisolated func store(_ result: Result<T, Error>) {
        lock.lock()
        storage = result
        lock.unlock()
    }

    nonisolated var value: Result<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        return storage ?? .failure(NSError(domain: errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "进程等待结果缺失"]))
    }
}
