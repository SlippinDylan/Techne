import Foundation
import Observation

@MainActor
@Observable
final class BranchPickerViewModel {
    typealias SnapshotLoader = @Sendable (_ projectPath: String) async -> BranchPickerSnapshot

    private(set) var projectPath: String
    private(set) var currentBranch: String
    private(set) var branches: [String] = []
    private(set) var isLoading = false
    private(set) var currentPageIndex = 0

    let pageSize: Int

    private let snapshotLoader: SnapshotLoader

    init(
        projectPath: String,
        currentBranch: String,
        pageSize: Int = 6,
        snapshotLoader: @escaping SnapshotLoader = ProjectBranchService().loadSnapshot(for:)
    ) {
        self.projectPath = projectPath
        self.currentBranch = currentBranch
        self.pageSize = max(1, pageSize)
        self.snapshotLoader = snapshotLoader
        self.branches = Self.normalizeBranches([], currentBranch: currentBranch)
    }

    var visibleBranches: [String] {
        let start = currentPageIndex * pageSize
        let end = min(start + pageSize, branches.count)
        guard start < end else { return [] }
        return Array(branches[start..<end])
    }

    var hasNextPage: Bool {
        currentPageIndex + 1 < pageCount
    }

    var hasPreviousPage: Bool {
        currentPageIndex > 0
    }

    var pageIndicator: String {
        "\(currentPageIndex + 1) / \(pageCount)"
    }

    var showsPaginationControls: Bool {
        pageCount > 1
    }

    func open() {
        refreshInBackground()
    }

    func updateProjectContext(path: String, currentBranch: String) {
        let normalizedCurrentBranch = currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathChanged = projectPath != path

        projectPath = path
        self.currentBranch = normalizedCurrentBranch

        if pathChanged {
            branches = Self.normalizeBranches([], currentBranch: normalizedCurrentBranch)
            currentPageIndex = 0
            return
        }

        branches = Self.normalizeBranches(branches, currentBranch: normalizedCurrentBranch)
        currentPageIndex = min(currentPageIndex, max(pageCount - 1, 0))
    }

    func replaceCachedBranches(_ branches: [String]) {
        self.branches = Self.normalizeBranches(branches, currentBranch: currentBranch)
        currentPageIndex = min(currentPageIndex, max(pageCount - 1, 0))
    }

    func refreshInBackground() {
        guard isLoading == false else { return }
        isLoading = true
        Task {
            await performRefresh(for: projectPath)
        }
    }

    func refresh() async {
        isLoading = true
        await performRefresh(for: projectPath)
    }

    func goToNextPage() {
        guard hasNextPage else { return }
        currentPageIndex += 1
    }

    func goToPreviousPage() {
        guard hasPreviousPage else { return }
        currentPageIndex -= 1
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(max(branches.count, 1)) / Double(pageSize))))
    }

    private func performRefresh(for activePath: String) async {
        guard activePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            replaceCachedBranches([])
            isLoading = false
            return
        }

        let snapshot = await snapshotLoader(activePath)

        guard activePath == projectPath else {
            isLoading = false
            return
        }

        let resolvedCurrentBranch = snapshot.currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedCurrentBranch.isEmpty == false {
            currentBranch = resolvedCurrentBranch
        }

        branches = Self.normalizeBranches(snapshot.branches, currentBranch: currentBranch)
        currentPageIndex = min(currentPageIndex, max(pageCount - 1, 0))
        isLoading = false
    }

    private static func normalizeBranches(_ branches: [String], currentBranch: String) -> [String] {
        let trimmedCurrentBranch = currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)

        var uniqueBranches: [String] = []
        var seenBranches = Set<String>()

        if trimmedCurrentBranch.isEmpty == false {
            seenBranches.insert(trimmedCurrentBranch)
            uniqueBranches.append(trimmedCurrentBranch)
        }

        let sortedBranches = branches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        for branch in sortedBranches where seenBranches.insert(branch).inserted {
            uniqueBranches.append(branch)
        }

        return uniqueBranches
    }
}
