import Testing
@testable import Techne

@MainActor
struct ApplicationQuitCoordinatorTests {
    @Test
    func successfulShutdownTerminatesOnce() async {
        var shutdownCount = 0
        var terminationCount = 0
        let coordinator = ApplicationQuitCoordinator(
            terminateApplication: { terminationCount += 1 },
            presentFailures: { _ in }
        )
        coordinator.registerShutdownHandler {
            shutdownCount += 1
            return []
        }

        coordinator.requestQuit()
        coordinator.requestQuit()
        await waitUntil { terminationCount == 1 }

        #expect(shutdownCount == 1)
        #expect(terminationCount == 1)
    }

    @Test
    func shutdownFailureKeepsApplicationRunningAndAllowsRetry() async {
        let failure = ProjectShutdownFailure(projectName: "frontend", message: "stop failed")
        var presentedFailures: [[ProjectShutdownFailure]] = []
        var terminationCount = 0
        let coordinator = ApplicationQuitCoordinator(
            terminateApplication: { terminationCount += 1 },
            presentFailures: { presentedFailures.append($0) }
        )
        coordinator.registerShutdownHandler { [failure] in [failure] }

        coordinator.requestQuit()
        await waitUntil { presentedFailures.isEmpty == false }

        #expect(terminationCount == 0)
        #expect(presentedFailures == [[failure]])
        #expect(coordinator.isQuitting == false)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            await Task.yield()
        }
    }
}
