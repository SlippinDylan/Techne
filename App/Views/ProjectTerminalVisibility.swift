import Foundation

enum ProjectTerminalVisibility {
    static func showsConsole(for project: Project) -> Bool {
        hasVisibleSessionState(project)
    }

    static func showsToggle(for project: Project) -> Bool {
        showsConsole(for: project)
    }

    private static func hasVisibleSessionState(_ project: Project) -> Bool {
        if project.isRunning || project.transitionState != .idle {
            return true
        }

        return project.terminalOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
