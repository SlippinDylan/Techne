//
//  DevServerParser.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import Foundation

/// 开发服务器解析器
/// 负责解析 lsof 输出并提取服务器信息
final class DevServerParser: Sendable {
    private let devProcesses: [String]

    /// 初始化解析器
    /// - Parameter devProcesses: 开发进程关键词列表，默认从 AppConfig 读取
    nonisolated init(devProcesses: [String] = AppConfig.DevServer.devProcesses) {
        self.devProcesses = devProcesses
    }

    // MARK: - Public Methods

    /// 解析 lsof 输出
    nonisolated func parseDevServers(from output: String) -> [DevServer] {
        let lines = output.components(separatedBy: "\n")
        var servers: [DevServer] = []

        for line in lines {
            // 只匹配开发相关的进程
            guard isDevProcess(line) else { continue }

            if let server = parseServerLine(line) {
                servers.append(server)
            }
        }

        return servers
    }

    // MARK: - Private Methods

    /// 检查是否是开发进程
    private nonisolated func isDevProcess(_ line: String) -> Bool {
        return devProcesses.contains { line.contains($0) }
    }

    /// 解析单行服务器信息
    private nonisolated func parseServerLine(_ line: String) -> DevServer? {
        // 格式: COMMAND  PID  USER  FD  TYPE  DEVICE  SIZE/OFF  NODE  NAME
        // 例如: node    1234 user  28u IPv4  0x123...  0t0  TCP *:5173 (LISTEN)

        // 使用正则表达式解析，避免空格分割问题
        let pattern = #"^(\S+)\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 4 else {
            return nil
        }

        // 提取进程名
        guard let processNameRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let processName = String(line[processNameRange])

        // 提取 PID
        guard let pidRange = Range(match.range(at: 2), in: line),
              let pid = Int32(String(line[pidRange])) else {
            return nil
        }

        // 提取端口信息（NAME 字段）
        guard let portStringRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        let portString = String(line[portStringRange])

        guard let port = extractPort(from: portString) else {
            return nil
        }

        // 获取详细信息
        let commandLine = getProcessCommandLine(pid: pid)
        let projectPath = extractProjectPath(pid: pid)
        let projectName = extractProjectName(from: projectPath)
        let serverType = detectServerType(from: commandLine)

        return DevServer(
            id: pid,
            processName: processName,
            port: port,
            projectPath: projectPath,
            projectName: projectName,
            serverType: serverType,
            commandLine: commandLine
        )
    }

    /// 提取端口号
    private nonisolated func extractPort(from portString: String) -> Int? {
        // 格式: *:5173 (LISTEN) 或 127.0.0.1:5173 (LISTEN) 或 TCP *:5173 (LISTEN)
        let components = portString.components(separatedBy: ":")
        guard let lastComponent = components.last else {
            return nil
        }

        // 提取数字部分，去掉 " (LISTEN)" 等后缀
        let portString = lastComponent.trimmingCharacters(in: .whitespaces)
        let digits = portString.components(separatedBy: .whitespaces).first ?? portString
        return Int(digits)
    }

    /// 获取进程的完整命令行
    private nonisolated func getProcessCommandLine(pid: Int32) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "command="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "DevServerParser")

            guard terminationStatus == 0 else {
                return ""
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // 不在这里调用 LogService，避免后台线程并发问题
            // 错误会通过返回空字符串来处理
        }

        return ""
    }

    /// 提取项目路径
    private nonisolated func extractProjectPath(pid: Int32) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            let terminationStatus = try ProcessUtils.runAndWaitForTerminationSync(task, errorDomain: "DevServerParser")

            guard terminationStatus == 0 else {
                return ""
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 输出格式: p<pid>\nfcwd\nn<path>
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    if line.hasPrefix("n") {
                        return String(line.dropFirst())
                    }
                }
            }
        } catch {
            // 不在这里调用 LogService，避免后台线程并发问题
            // 错误会通过返回空字符串来处理
        }

        return ""
    }

    /// 提取项目名称
    private nonisolated func extractProjectName(from projectPath: String) -> String {
        guard !projectPath.isEmpty else {
            return "Unknown Project"
        }

        let url = URL(fileURLWithPath: projectPath)
        return url.lastPathComponent
    }

    /// 检测服务器类型
    private nonisolated func detectServerType(from commandLine: String) -> DevServer.ServerType {
        let typeKeywords: [(String, DevServer.ServerType)] = [
            ("vite", .vite),
            ("next", .nextjs),
            ("webpack", .webpack),
            ("react-scripts", .react),
            ("vue-cli-service", .vue),
            ("@vue/cli", .vue),
            ("nuxt", .nuxt)
        ]

        for (keyword, type) in typeKeywords {
            if commandLine.contains(keyword) {
                return type
            }
        }

        return .unknown
    }
}
