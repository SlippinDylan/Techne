import Foundation
import Testing
@testable import DevNexus

struct ProjectTerminalVisibilityTests {
    @Test
    func hidesConsoleWhenProjectIsIdleWithoutOutput() {
        let project = makeProject(type: .miniApp)

        #expect(ProjectTerminalVisibility.showsConsole(for: project) == false)
        #expect(ProjectTerminalVisibility.showsToggle(for: project) == false)
    }

    @Test
    func showsConsoleOnceProjectHasOutputHistory() {
        var project = makeProject(type: .miniApp)
        project.terminalOutput = "build started\n"

        #expect(ProjectTerminalVisibility.showsConsole(for: project))
        #expect(ProjectTerminalVisibility.showsToggle(for: project))
    }

    @Test
    func showsConsoleWhileProjectIsRunningOrTransitioning() {
        var runningProject = makeProject(type: .miniApp)
        runningProject.isRunning = true

        var startingProject = makeProject(type: .miniApp)
        startingProject.transitionState = .starting

        #expect(ProjectTerminalVisibility.showsConsole(for: runningProject))
        #expect(ProjectTerminalVisibility.showsToggle(for: runningProject))
        #expect(ProjectTerminalVisibility.showsConsole(for: startingProject))
        #expect(ProjectTerminalVisibility.showsToggle(for: startingProject))
    }

    @Test
    func showsConsoleForDevServerProjectsUsingTheSameRules() {
        var project = makeProject(type: .devServer)
        project.terminalOutput = "[系统] server ready\n"

        #expect(ProjectTerminalVisibility.showsConsole(for: project))
        #expect(ProjectTerminalVisibility.showsToggle(for: project))
    }

    private func makeProject(type: ProjectType) -> Project {
        Project(
            name: type == .miniApp ? "mini-app" : "dev-server",
            path: type == .miniApp ? "/Users/test/mini-app" : "/Users/test/dev-server",
            type: type,
            currentBranch: "main",
            startCommand: type == .miniApp ? "pnpm dev:mp" : "pnpm dev"
        )
    }
}
