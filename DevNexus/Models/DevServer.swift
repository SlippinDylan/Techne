//
//  DevServer.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/14.
//

import Foundation

struct DevServer: Identifiable, Hashable {
    let id: Int32  // PID
    let processName: String  // 进程名称（node, bun, deno 等）
    let port: Int  // 端口号
    let projectPath: String  // 项目路径
    let projectName: String  // 项目名称
    let serverType: ServerType  // 服务器类型
    let commandLine: String  // 完整命令行

    enum ServerType: String {
        case vite = "Vite"
        case nextjs = "Next.js"
        case webpack = "Webpack"
        case react = "React"
        case vue = "Vue"
        case nuxt = "Nuxt"
        case unknown = "Unknown"

        private static let iconMap: [ServerType: String] = [
            .vite: "square.stack.3d.up.fill",
            .nextjs: "arrow.triangle.2.circlepath",
            .webpack: "cube.fill",
            .react: "atom",
            .vue: "v.circle.fill",
            .nuxt: "n.circle.fill",
            .unknown: "server.rack"
        ]

        var icon: String {
            Self.iconMap[self] ?? "server.rack"
        }
    }
}
