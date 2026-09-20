//
//  ProcessUtils.swift
//  Techne
//
//  Created by SlippinDylan on 2026/3/12.
//

import Foundation
import os

enum ProcessUtils {
    struct CaptureResult: Sendable {
        let terminationStatus: Int32
        let standardOutput: Data
        let standardError: Data
    }

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

    nonisolated static func runAndCapture(_ process: Process) async throws -> CaptureResult {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()
        process.standardOutput = standardOutput
        process.standardError = standardError

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false {
                outputBuffer.append(data)
            }
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false {
                errorBuffer.append(data)
            }
        }

        let terminationStatus: Int32
        do {
            terminationStatus = try await runAndWaitForTermination(process)
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
        if let remainingOutput = try? standardOutput.fileHandleForReading.readToEnd() {
            outputBuffer.append(remainingOutput)
        }
        if let remainingError = try? standardError.fileHandleForReading.readToEnd() {
            errorBuffer.append(remainingError)
        }

        return CaptureResult(
            terminationStatus: terminationStatus,
            standardOutput: outputBuffer.data,
            standardError: errorBuffer.data
        )
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

private final class LockedDataBuffer: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock<Data>(initialState: Data())

    nonisolated func append(_ data: Data) {
        storage.withLock { buffer in
            buffer.append(data)
        }
    }

    nonisolated var data: Data {
        storage.withLock { $0 }
    }
}

private struct LockedResultBox<T: Sendable>: Sendable {
    private let errorDomain: String
    private let storage = OSAllocatedUnfairLock<Result<T, Error>?>(initialState: nil)

    nonisolated init(errorDomain: String) {
        self.errorDomain = errorDomain
    }

    nonisolated func store(_ result: Result<T, Error>) {
        storage.withLock { state in
            state = result
        }
    }

    nonisolated var value: Result<T, Error> {
        storage.withLock { state in
            state ?? .failure(
                NSError(
                    domain: errorDomain,
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: AppLocalized("error.process.wait_result_missing")]
                )
            )
        }
    }
}
