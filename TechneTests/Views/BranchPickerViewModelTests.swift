import Foundation
import Testing
@testable import Techne

@MainActor
struct BranchPickerViewModelTests {
    @Test
    func opensImmediatelyWhileKeepingCachedBranchesVisibleDuringRefresh() async {
        let refreshStarted = LockedFlag()
        let releaseRefresh = AsyncGate()

        let viewModel = BranchPickerViewModel(
            projectPath: "/Users/test/project",
            currentBranch: "main",
            pageSize: 6,
            snapshotLoader: { _ in
                await refreshStarted.setTrue()
                await releaseRefresh.wait()
                return BranchPickerSnapshot(currentBranch: "main", branches: ["main", "release"])
            }
        )

        viewModel.replaceCachedBranches(["main", "develop", "feature/a"])
        viewModel.open()

        #expect(viewModel.isLoading)
        #expect(viewModel.visibleBranches == ["main", "develop", "feature/a"])
        await waitUntil(timeout: .seconds(1)) {
            await refreshStarted.value
        }

        await releaseRefresh.open()
        await waitUntil(timeout: .seconds(1)) {
            viewModel.isLoading == false
        }

        #expect(viewModel.visibleBranches == ["main", "release"])
    }

    @Test
    func prioritizesCurrentBranchAndPaginatesWithoutScrolling() async {
        let branches = ["feature/c", "feature/a", "develop", "feature/b", "main"]
        let viewModel = BranchPickerViewModel(
            projectPath: "/Users/test/project",
            currentBranch: "develop",
            pageSize: 3,
            snapshotLoader: { _ in
                BranchPickerSnapshot(currentBranch: "develop", branches: branches)
            }
        )

        await viewModel.refresh()

        #expect(viewModel.visibleBranches == ["develop", "feature/a", "feature/b"])
        #expect(viewModel.hasNextPage)
        #expect(viewModel.hasPreviousPage == false)
        #expect(viewModel.pageIndicator == "1 / 2")

        viewModel.goToNextPage()

        #expect(viewModel.visibleBranches == ["feature/c", "main"])
        #expect(viewModel.hasNextPage == false)
        #expect(viewModel.hasPreviousPage)
        #expect(viewModel.pageIndicator == "2 / 2")
    }

    @Test
    func injectsDetachedHeadBranchWhenLoaderDoesNotReturnIt() async {
        let viewModel = BranchPickerViewModel(
            projectPath: "/Users/test/project",
            currentBranch: "a1b2c3d",
            pageSize: 6,
            snapshotLoader: { _ in
                BranchPickerSnapshot(currentBranch: "a1b2c3d", branches: ["main", "develop"])
            }
        )

        await viewModel.refresh()

        #expect(viewModel.visibleBranches.first == "a1b2c3d")
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(20),
        condition: @escaping () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}

private actor AsyncGate {
    private var isOpen = false

    func wait() async {
        while isOpen == false {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func open() {
        isOpen = true
    }
}

private actor LockedFlag {
    private(set) var value = false

    func setTrue() {
        value = true
    }
}
