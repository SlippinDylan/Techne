//
//  ShellEscape.swift
//  DevNexus
//
//  Shell 命令转义工具
//

import Foundation

enum ShellEscape {
    /// 转义 shell 参数，防止命令注入
    /// - Parameter argument: 需要转义的参数
    /// - Returns: 转义后的安全参数
    static func escape(_ argument: String) -> String {
        // 如果参数为空，返回空字符串
        guard !argument.isEmpty else { return "''" }

        // 如果参数只包含安全字符，直接返回
        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-/"))

        if argument.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return argument
        }

        // 使用单引号包裹，并转义内部的单引号
        // 将 ' 替换为 '\''
        let escaped = argument.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// 转义多个参数
    /// - Parameter arguments: 参数数组
    /// - Returns: 转义后的参数数组
    static func escape(_ arguments: [String]) -> [String] {
        arguments.map { escape($0) }
    }
}
