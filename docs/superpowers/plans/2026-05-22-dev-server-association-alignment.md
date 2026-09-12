# Dev Server Association Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Portlens nested-app case by unifying the rule that decides whether a detected dev server belongs to a managed project, so startup transitions settle correctly and the discovered-server section stops showing already-managed child paths.

**Architecture:** Introduce one pure helper that owns all project-to-dev-server path matching and server filtering logic, including exact match, ancestor/descendant match, closest-project selection, and suppression checks. Then route both `ProjectService.reconcileDetectedDevServers(_:)` and `ProjectListView` through that helper so “running”, “starting→idle”, and “discovered unmanaged server” all use the same semantics.

**Tech Stack:** Swift, SwiftUI, Observation, Swift Testing, `xcodebuild test`

---

### Task 1: Extract a single dev-server ownership matcher with deterministic nested-path rules

**Files:**
- Create: `Techne/Models/DevServerProjectMatcher.swift`
- Test: `TechneTests/Models/DevServerProjectMatcherTests.swift`

- [ ] **Step 1: Write the failing matcher tests**

Create `TechneTests/Models/DevServerProjectMatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import Techne

struct DevServerProjectMatcherTests {
    @Test
    func descendantServerPathMatchesAncestorManagedProject() {
        let projectPath = "/Users/test/Portlens"
        let server = DevServer(
            id: 26834,
            processName: "node",
            port: 3000,
            projectPath: "/Users/test/Portlens/app",
            projectName: "app",
            serverType: .nextjs,
            commandLine: "node ./scripts/workspace-next.mjs dev mock"
        )

        #expect(
            DevServerProjectMatcher.belongs(serverPath: server.projectPath, toProjectPath: projectPath)
        )
    }

    @Test
    func unrelatedSiblingPathDoesNotMatchManagedProject() {
        #expect(
            DevServerProjectMatcher.belongs(
                serverPath: "/Users/test/Portlens-docs/app",
                toProjectPath: "/Users/test/Portlens"
            ) == false
        )
    }

    @Test
    func bestMatchingProjectPrefersMostSpecificManagedAncestor() {
        let server = DevServer(
            id: 3001,
            processName: "node",
            port: 3001,
            projectPath: "/Users/test/Portlens/app",
            projectName: "app",
            serverType: .nextjs,
            commandLine: "node ./scripts/workspace-next.mjs dev mock"
        )

        let bestMatch = DevServerProjectMatcher.bestMatchingProjectPath(
            for: server,
            managedProjectPaths: [
                "/Users/test/Portlens",
                "/Users/test/Portlens/app"
            ]
        )

        #expect(bestMatch == "/Users/test/Portlens/app")
    }

    @Test
    func suppressedProjectPathAlsoSuppressesNestedDetectedServer() {
        let server = DevServer(
            id: 13650,
            processName: "node",
            port: 3000,
            projectPath: "/Users/test/Portlens/app",
            projectName: "app",
            serverType: .nextjs,
            commandLine: "node ./scripts/workspace-next.mjs dev mock"
        )

        #expect(
            DevServerProjectMatcher.isSuppressed(
                server: server,
                suppressedProjectPaths: ["/Users/test/Portlens"]
            )
        )
    }
}
```

- [ ] **Step 2: Run the matcher tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/DevServerProjectMatcherTests
```

Expected: FAIL because `DevServerProjectMatcher` does not exist yet.

- [ ] **Step 3: Implement a pure matcher with one normalized ownership rule**

Create `Techne/Models/DevServerProjectMatcher.swift`:

```swift
import Foundation

enum DevServerProjectMatcher {
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    static func belongs(serverPath: String, toProjectPath projectPath: String) -> Bool {
        let normalizedServerPath = normalize(serverPath)
        let normalizedProjectPath = normalize(projectPath)

        if normalizedServerPath == normalizedProjectPath {
            return true
        }

        return normalizedServerPath.hasPrefix(normalizedProjectPath + "/")
    }

    static func bestMatchingProjectPath(
        for server: DevServer,
        managedProjectPaths: [String]
    ) -> String? {
        managedProjectPaths
            .map(normalize)
            .filter { belongs(serverPath: server.projectPath, toProjectPath: $0) }
            .max(by: { $0.count < $1.count })
    }

    static func isSuppressed(
        server: DevServer,
        suppressedProjectPaths: Set<String>
    ) -> Bool {
        suppressedProjectPaths.contains { suppressedPath in
            belongs(serverPath: server.projectPath, toProjectPath: suppressedPath)
        }
    }
}
```

Design constraints:
- Only allow exact match or `serverPath` being a descendant of `projectPath`
- Do **not** allow the inverse “project is descendant of server” relationship; that was the source of the current false-positive related-server rule
- When multiple managed project paths match, always prefer the longest normalized path

- [ ] **Step 4: Run the matcher tests to verify they pass**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/DevServerProjectMatcherTests
```

Expected: PASS for nested child-path ownership, sibling rejection, most-specific managed match, and suppression coverage.

- [ ] **Step 5: Commit**

```bash
git add Techne/Models/DevServerProjectMatcher.swift TechneTests/Models/DevServerProjectMatcherTests.swift
git commit -m "test: codify nested dev server ownership rules"
```

### Task 2: Route project state reconciliation and discovered-server filtering through the shared matcher

**Files:**
- Modify: `Techne/Services/ProjectService.swift`
- Modify: `Techne/Views/ProjectListView.swift`
- Test: `TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift`
- Modify: `TechneTests/Models/DevServerProjectMatcherTests.swift`

- [ ] **Step 1: Write the failing reconciliation and filtering tests**

Append these tests to `TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift`:

```swift
    @Test
    @MainActor
    func nestedDetectedServerClearsStartingStateForManagedRootProject() {
        let service = makeProjectService(
            persistenceRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        var project = Project(
            name: "Portlens",
            path: "/Users/test/Portlens",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev:mock"
        )
        project.transitionState = .starting
        service.projects = [project]

        let nestedServer = DevServer(
            id: 26834,
            processName: "node",
            port: 3000,
            projectPath: "/Users/test/Portlens/app",
            projectName: "app",
            serverType: .nextjs,
            commandLine: "node ./scripts/workspace-next.mjs dev mock"
        )

        service.reconcileDetectedDevServers([nestedServer])

        #expect(service.projects[0].runningProcessPID == 26834)
        #expect(service.projects[0].isRunning)
        #expect(service.projects[0].transitionState == .idle)
    }
```

Append these tests to `TechneTests/Models/DevServerProjectMatcherTests.swift`:

```swift
    @Test
    func unmanagedServersExcludeNestedPathsOwnedByManagedProjects() {
        let managedPaths = [
            "/Users/test/blog",
            "/Users/test/Portlens"
        ]

        let servers = [
            DevServer(
                id: 13650,
                processName: "node",
                port: 3000,
                projectPath: "/Users/test/Portlens/app",
                projectName: "app",
                serverType: .nextjs,
                commandLine: "node ./scripts/workspace-next.mjs dev mock"
            ),
            DevServer(
                id: 22724,
                processName: "node",
                port: 3001,
                projectPath: "/Users/test/elsewhere/demo",
                projectName: "demo",
                serverType: .vite,
                commandLine: "pnpm dev"
            )
        ]

        let unmanaged = servers.filter { server in
            DevServerProjectMatcher.bestMatchingProjectPath(for: server, managedProjectPaths: managedPaths) == nil
        }

        #expect(unmanaged.map(\.id) == [22724])
    }
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/DevServerProjectMatcherTests -only-testing:TechneTests/ProjectServiceStartupRecoveryTests
```

Expected: FAIL because `ProjectService.reconcileDetectedDevServers(_:)` still only accepts exact path equality, and `ProjectListView` still uses a different path rule.

- [ ] **Step 3: Replace the duplicated path heuristics with the shared matcher**

Update `Techne/Services/ProjectService.swift` inside `reconcileDetectedDevServers(_:)`:

```swift
    @MainActor
    func reconcileDetectedDevServers(_ servers: [DevServer]) {
        let managedProjectPaths = projects
            .filter { $0.type == .devServer }
            .map(\.path)

        for index in projects.indices where projects[index].type == .devServer {
            let pidMatchedServer = projects[index].runningProcessPID.flatMap { pid in
                servers.first(where: { $0.id == pid })
            }

            let pathMatchedServer = servers.first { server in
                DevServerProjectMatcher.bestMatchingProjectPath(
                    for: server,
                    managedProjectPaths: [projects[index].path]
                ) != nil
            }

            let matchedServer = pidMatchedServer ?? pathMatchedServer

            if let matchedServer {
                projects[index].runningProcessPID = matchedServer.id
                projects[index].isRunning = true

                if projects[index].transitionState == .starting {
                    projects[index].transitionState = .idle
                }
                clearDevServerDetectionTrigger(for: projects[index].id)
            } else if projects[index].transitionState == .stopping {
                projects[index].runningProcessPID = nil
                projects[index].isRunning = false
                projects[index].transitionState = .idle
                clearDevServerDetectionTrigger(for: projects[index].id)
            }
        }
    }
```

Update `Techne/Views/ProjectListView.swift`:

```swift
    private var unmanagedDiscoveredServers: [DevServer] {
        let managedProjectPaths = filteredProjects.map(\.path)

        return devServerService.servers.filter { server in
            let ownedProjectPath = DevServerProjectMatcher.bestMatchingProjectPath(
                for: server,
                managedProjectPaths: managedProjectPaths
            )
            let isSuppressed = DevServerProjectMatcher.isSuppressed(
                server: server,
                suppressedProjectPaths: startupSuppressedProjectPaths
            )
            return ownedProjectPath == nil && isSuppressed == false
        }
    }
```

Replace `findRelatedServer(for:)` with the same ownership rule:

```swift
    private func findRelatedServer(for project: Project) -> DevServer? {
        if let runningProcessPID = project.runningProcessPID,
           let pidMatchedServer = devServerService.servers.first(where: { $0.id == runningProcessPID }) {
            return pidMatchedServer
        }

        return devServerService.servers.first { server in
            DevServerProjectMatcher.bestMatchingProjectPath(
                for: server,
                managedProjectPaths: [project.path]
            ) != nil
        }
    }
```

Update `clearResolvedSuppressedPaths()` to use the same matcher instead of exact path equality:

```swift
    private func clearResolvedSuppressedPaths() {
        let resolvedPaths = Set(
            filteredProjects.compactMap { project -> String? in
                let hasResolvedServer = devServerService.servers.contains { server in
                    DevServerProjectMatcher.bestMatchingProjectPath(
                        for: server,
                        managedProjectPaths: [project.path]
                    ) != nil
                }
                return hasResolvedServer ? normalizedPath(for: project.path) : nil
            }
        )

        startupSuppressedProjectPaths.subtract(resolvedPaths)
    }
```

Important constraints:
- Keep `startupSuppressedProjectPaths` keyed by project root path; do **not** change it to server path
- Do **not** invent a second matcher in `ProjectService`
- Do **not** preserve the current symmetric parent/child rule from `findRelatedServer(for:)`; only `serverPath == projectPath` or `serverPath` inside `projectPath` is valid

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/DevServerProjectMatcherTests -only-testing:TechneTests/ProjectServiceStartupRecoveryTests
```

Expected: PASS, including the regression that a nested `Portlens/app` server clears `.starting` on the managed `Portlens` root project.

- [ ] **Step 5: Run the impacted regression suite**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:TechneTests/DevServerProjectMatcherTests -only-testing:TechneTests/ProjectServiceStartupRecoveryTests -only-testing:TechneTests/ProjectSnapshotMigrationTests -only-testing:TechneTests/MainWindowCoordinatorTests
```

Expected: PASS. Serial execution is acceptable if `ProjectServiceStartupRecoveryTests` remains flaky under parallel execution.

- [ ] **Step 6: Commit**

```bash
git add Techne/Models/DevServerProjectMatcher.swift Techne/Views/ProjectListView.swift Techne/Services/ProjectService.swift TechneTests/Models/DevServerProjectMatcherTests.swift TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift
git commit -m "fix: align dev server ownership across list and startup state"
```
