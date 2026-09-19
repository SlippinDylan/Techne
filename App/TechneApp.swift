//
//  TechneApp.swift
//  Techne
//
//  Created by SlippinDylan on 2025/12/13.
//

import SwiftUI

@main
struct TechneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 注入全局自启设置
    @State private var launchSettings = LaunchSettings.shared
    @State private var commandConfigService: CommandConfigService
    @State private var projectService: ProjectService
    @State private var mainWindowNavigationCoordinator = MainWindowNavigationCoordinator.shared
    @State private var updateController = ApplicationUpdateController()

    init() {
        let commandConfigService = CommandConfigService()
        _commandConfigService = State(wrappedValue: commandConfigService)
        _projectService = State(wrappedValue: ProjectService(commandConfigService: commandConfigService))
    }

    var body: some Scene {
        // 主窗口
        Window("Techne", id: "main") {
            ContentView(
                commandConfigService: commandConfigService,
                projectService: projectService,
                updateController: updateController
            )
            .environment(launchSettings)
            .environment(mainWindowNavigationCoordinator)
            .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            MainWindowNavigationCommands()
            TechneAppCommands()
        }
    }
}

struct TechneAppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Techne") {
                MainWindowNavigationCoordinator.shared.showMainWindow(selecting: .about)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                MainWindowNavigationCoordinator.shared.showMainWindow(selecting: .settings)
            }
        }

        CommandGroup(after: .windowArrangement) {
            Divider()

            Button("操作日志") {
                MainWindowNavigationCoordinator.shared.showMainWindow(selecting: .logs)
            }
        }

        CommandGroup(replacing: .appTermination) {
            Button("关闭 Techne 窗口") {
                MainWindowNavigationCoordinator.shared.closeMainWindow()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

struct MainWindowNavigationCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = MainWindowNavigationCoordinator.shared.registerOpenMainWindowAction {
            openWindow(id: "main")
        }

        CommandGroup(before: .appInfo) { }
    }
}
