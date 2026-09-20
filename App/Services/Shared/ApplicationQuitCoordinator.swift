import AppKit

@MainActor
final class ApplicationQuitCoordinator {
    typealias ShutdownHandler = @MainActor () async -> [ProjectShutdownFailure]
    typealias FailurePresenter = @MainActor ([ProjectShutdownFailure]) -> Void

    static let shared = ApplicationQuitCoordinator()

    private var shutdownHandler: ShutdownHandler?
    private let terminateApplication: () -> Void
    private let presentFailures: FailurePresenter
    private(set) var isQuitting = false

    init(
        terminateApplication: @escaping () -> Void = { NSApp.terminate(nil) },
        presentFailures: @escaping FailurePresenter = { failures in
            ApplicationQuitCoordinator.present(failures)
        }
    ) {
        self.terminateApplication = terminateApplication
        self.presentFailures = presentFailures
    }

    func register(projectService: ProjectService) {
        shutdownHandler = { [weak projectService] in
            guard let projectService else {
                return []
            }
            return await projectService.shutdownAllProjects()
        }
    }

    func registerShutdownHandler(_ handler: @escaping ShutdownHandler) {
        shutdownHandler = handler
    }

    func requestQuit() {
        guard isQuitting == false else {
            return
        }
        guard let shutdownHandler else {
            terminateApplication()
            return
        }

        isQuitting = true
        Task { @MainActor in
            let failures = await shutdownHandler()
            if failures.isEmpty {
                terminateApplication()
            } else {
                presentFailures(failures)
                isQuitting = false
            }
        }
    }

    private static func present(_ failures: [ProjectShutdownFailure]) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalized("退出 Techne")
        alert.informativeText = failures
            .map { "\($0.projectName): \($0.message)" }
            .joined(separator: "\n")
        alert.addButton(withTitle: AppLocalized("确定"))
        alert.runModal()
    }
}
