//
//  ApplicationRelaunchController.swift
//  Techne
//

import AppKit

@MainActor
final class ApplicationRelaunchController {
    static let shared = ApplicationRelaunchController()

    private let terminateApplication: () -> Void
    private var isRelaunchRequested = false

    init(terminateApplication: @escaping () -> Void = {
        NSApp.terminate(nil)
    }) {
        self.terminateApplication = terminateApplication
    }

    /// Requests one controlled termination. The app delegate launches the replacement instance.
    @discardableResult
    func requestRelaunch() -> Bool {
        guard !isRelaunchRequested else {
            return false
        }

        isRelaunchRequested = true
        terminateApplication()
        return true
    }

    func consumeRelaunchRequest() -> Bool {
        defer { isRelaunchRequested = false }
        return isRelaunchRequested
    }
}
