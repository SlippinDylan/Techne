//
//  TerminalOutputHandler.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 终端输出处理器
/// 处理进程的终端输出，包括 ANSI 码清理和输出限制
final class TerminalOutputHandler: Sendable {

    // 缓存正则表达式以提高性能
    nonisolated private static let ansiRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\x1B(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~])", options: [])
    }()

    /// 清理 ANSI 转义码
    nonisolated func stripANSICodes(_ text: String) -> String {
        guard let regex = Self.ansiRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// 限制输出长度
    nonisolated func limitOutput(_ output: String, maxLength: Int = AppConfig.Process.terminalOutputLimit) -> String {
        guard output.count > maxLength else { return output }

        let startIndex = output.index(
            output.endIndex,
            offsetBy: -maxLength
        )
        return String(output[startIndex...])
    }

    /// 设置管道输出处理器
    nonisolated func setupOutputHandler(
        for pipe: Pipe,
        onOutput: @escaping @Sendable (String) -> Void
    ) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard data.count > 0,
                  let output = String(data: data, encoding: .utf8) else {
                return
            }

            let cleanOutput = self?.stripANSICodes(output) ?? output
            onOutput(cleanOutput)
        }
    }

    /// 清理管道处理器
    nonisolated func cleanupHandlers(outputPipe: Pipe, errorPipe: Pipe) {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
    }
}
