import Foundation

struct BranchPickerSnapshot: Equatable, Sendable {
    let currentBranch: String
    let branches: [String]
}

struct ProjectBranchService: Sendable {
    nonisolated func loadSnapshot(for projectPath: String) async -> BranchPickerSnapshot {
        await Task.detached(priority: .userInitiated) {
            let gitService = GitService.shared
            return BranchPickerSnapshot(
                currentBranch: gitService.getCurrentBranch(at: projectPath) ?? "",
                branches: gitService.getLocalBranches(at: projectPath)
            )
        }.value
    }
}
