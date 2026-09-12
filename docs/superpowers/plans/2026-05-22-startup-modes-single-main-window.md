# Startup Modes And Single Main Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable per-project startup mode selection for dev-server projects, with immediate stop-and-restart semantics when the selected mode changes during runtime, and enforce a single reusable main window for menu-bar navigation.

**Architecture:** Keep the current `Project.startCommand` flow as the compatibility surface, but introduce explicit `availableStartupModes` plus `selectedStartupModeID` so startup mode becomes a first-class persisted concept instead of a UI-only override. For window behavior, replace the multi-instance `WindowGroup(id: "main")` scene with a singleton `Window`, and route menu-bar focus through a small coordinator that prefers an existing main window and only opens one when none exists.

**Tech Stack:** Swift, SwiftUI, AppKit, Observation, Swift Testing, `xcodebuild test`

---

### Task 1: Model explicit startup modes and migrate persisted projects safely

**Files:**
- Modify: `Techne/Models/Project.swift`
- Modify: `Techne/Models/ProjectCommandSnapshotResolver.swift`
- Modify: `Techne/Views/ProjectCommandDetailsPopover.swift`
- Test: `TechneTests/Models/ProjectSnapshotMigrationTests.swift`

- [ ] **Step 1: Write the failing model and migration tests**

Add these tests to `TechneTests/Models/ProjectSnapshotMigrationTests.swift`:

```swift
    @Test
    func addProjectDetectsMultipleStartupModesAndDefaultsToDev() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try """
        {
          "name": "portlens-workspace",
          "scripts": {
            "dev": "node ./scripts/workspace-next.mjs dev dev-default",
            "dev:mock": "node ./scripts/workspace-next.mjs dev mock",
            "dev:live": "node ./scripts/workspace-next.mjs dev live",
            "build": "next build"
          },
          "dependencies": {
            "next": "^15.0.0"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)

        let project = ProjectCommandSnapshotResolver.makeProject(
            name: "portlens-workspace",
            path: projectRoot.path,
            type: .devServer
        )

        #expect(project.availableStartupModes.map(\.id) == ["dev", "dev:mock", "dev:live"])
        #expect(project.selectedStartupModeID == "dev")
        #expect(project.startCommand == "pnpm dev")
        #expect(project.selectedStartupMode?.displayName == "默认")
    }

    @Test
    func legacyProjectWithoutStartupModesBackfillsSelectedModeFromStartCommand() {
        let legacyProject = Project(
            name: "legacy-app",
            path: "/tmp/legacy-app",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev:mock",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf .next",
            installCommand: "pnpm install",
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Next.js + pnpm"
        )

        let updated = ProjectCommandSnapshotResolver.backfillingMissingSnapshot(for: legacyProject)

        #expect(updated.availableStartupModes.count == 1)
        #expect(updated.availableStartupModes[0].startCommand == "pnpm dev:mock")
        #expect(updated.selectedStartupModeID == updated.availableStartupModes[0].id)
        #expect(updated.startCommand == "pnpm dev:mock")
    }

    @Test
    func selectingStartupModeUpdatesCompatibilityStartCommand() {
        var project = Project(
            name: "frontend-app",
            path: "/tmp/frontend-app",
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist",
            installCommand: "pnpm install",
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Vite + pnpm",
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "pnpm dev", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "pnpm dev:mock", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )

        project.selectStartupMode(id: "dev:mock")

        #expect(project.selectedStartupModeID == "dev:mock")
        #expect(project.startCommand == "pnpm dev:mock")
        #expect(project.selectedStartupMode?.displayName == "Mock")
    }
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectSnapshotMigrationTests
```

Expected: FAIL with compiler errors for missing `ProjectStartupMode`, missing `availableStartupModes`, or missing selection helpers.

- [ ] **Step 3: Implement the persisted startup mode model and resolver updates**

Update `Techne/Models/Project.swift` with a focused model that preserves `startCommand` as the compatibility mirror:

```swift
enum ProjectStartupModeSource: String, Codable, Sendable {
    case autoDetected
    case importedLegacy
    case commandConfig
}

struct ProjectStartupMode: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let startCommand: String
    let source: ProjectStartupModeSource
}

extension Project {
    var selectedStartupMode: ProjectStartupMode? {
        availableStartupModes.first(where: { $0.id == selectedStartupModeID })
    }

    mutating func selectStartupMode(id: String) {
        guard let mode = availableStartupModes.first(where: { $0.id == id }) else { return }
        selectedStartupModeID = mode.id
        startCommand = mode.startCommand
    }
}
```

Update the persisted `Project` shape in `Techne/Models/Project.swift`:

```swift
    var availableStartupModes: [ProjectStartupMode]
    var selectedStartupModeID: String?
```

Initialize and decode them with backward-compatible defaults:

```swift
        let defaultMode = ProjectStartupMode(
            id: "default",
            displayName: "默认",
            startCommand: self.startCommand,
            source: .importedLegacy
        )
        self.availableStartupModes = try container.decodeIfPresent([ProjectStartupMode].self, forKey: .availableStartupModes) ?? [defaultMode]
        self.selectedStartupModeID = try container.decodeIfPresent(String.self, forKey: .selectedStartupModeID) ?? self.availableStartupModes.first?.id
        if let selectedMode = self.availableStartupModes.first(where: { $0.id == self.selectedStartupModeID }) {
            self.startCommand = selectedMode.startCommand
        }
```

Update `Techne/Models/ProjectCommandSnapshotResolver.swift` so the snapshot carries startup mode candidates:

```swift
struct ProjectCommandSnapshot: Equatable, Sendable {
    let startCommand: String
    let startupModes: [ProjectStartupMode]
    let selectedStartupModeID: String?
    let buildCommand: String
    let cleanCommand: String
    let installCommand: String
    let stopCommand: String
    let discardChangesCommand: String
    let commandProfileName: String
    let installStrategy: InstallStrategy
}
```

Add a reusable dev-server startup mode detector:

```swift
    private static func detectedStartupModes(
        packageManager: ProjectPackageManager,
        manifest: PackageManifest?
    ) -> [ProjectStartupMode] {
        let candidates: [(String, String)] = [
            ("dev", "默认"),
            ("dev:mock", "Mock"),
            ("dev:live", "Live"),
            ("mock", "Mock"),
            ("start", "Start")
        ]

        return candidates.compactMap { scriptName, displayName in
            guard manifest?.scripts?[scriptName] != nil else { return nil }
            return ProjectStartupMode(
                id: scriptName,
                displayName: displayName,
                startCommand: packageManager.runCommand(scriptName),
                source: .autoDetected
            )
        }
    }
```

Use that detector in `viteSnapshot`, `nextSnapshot`, and `genericDevServerSnapshot`, always choosing `dev` first when available:

```swift
        let startupModes = detectedStartupModes(packageManager: packageManager, manifest: manifest)
        let selectedMode = startupModes.first(where: { $0.id == "dev" }) ?? startupModes.first

        return ProjectCommandSnapshot(
            startCommand: selectedMode?.startCommand ?? packageManager.runCommand("dev"),
            startupModes: startupModes.isEmpty ? [
                ProjectStartupMode(id: "default", displayName: "默认", startCommand: packageManager.runCommand("dev"), source: .autoDetected)
            ] : startupModes,
            selectedStartupModeID: selectedMode?.id ?? startupModes.first?.id ?? "default",
            buildCommand: commandForFirstScript(["build"], packageManager: packageManager, manifest: manifest) ?? packageManager.runCommand("build"),
            cleanCommand: commandForScript("clean", packageManager: packageManager, manifest: manifest) ?? "rm -rf .next",
            installCommand: packageManager.installCommand,
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Next.js + \(packageManager.rawValue)",
            installStrategy: .ifMissing
        )
```

Update `Techne/Views/ProjectCommandDetailsPopover.swift` to show the currently selected startup mode label and all available startup commands:

```swift
            Section(title: "当前启动模式", value: project.selectedStartupMode?.displayName ?? "默认"),
            Section(title: "启动命令", value: project.startCommand),
            Section(
                title: "可选启动模式",
                value: project.availableStartupModes.map { "\($0.displayName): \($0.startCommand)" }.joined(separator: "\n")
            ),
```

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectSnapshotMigrationTests
```

Expected: PASS for the new startup mode detection, legacy migration, and compatibility mirror behavior.

- [ ] **Step 5: Commit**

```bash
git add Techne/Models/Project.swift Techne/Models/ProjectCommandSnapshotResolver.swift Techne/Views/ProjectCommandDetailsPopover.swift TechneTests/Models/ProjectSnapshotMigrationTests.swift
git commit -m "feat: persist project startup modes"
```

### Task 2: Expose startup modes in add-project preview and project cards without bloating the card

**Files:**
- Modify: `Techne/Views/AddProjectSheet.swift`
- Create: `Techne/Views/Shared/Components/StartupModePicker.swift`
- Modify: `Techne/Views/ProjectCard.swift`
- Modify: `Techne/Views/ProjectListView.swift`
- Test: `TechneTests/Models/ProjectSnapshotMigrationTests.swift`

- [ ] **Step 1: Write the failing presentation tests**

Add these tests to `TechneTests/Models/ProjectSnapshotMigrationTests.swift`:

```swift
    @Test
    func startupModeDisplayNamesPreferMockAndLiveLabels() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try """
        {
          "name": "workspace",
          "scripts": {
            "dev": "vite",
            "dev:mock": "vite --mode mock",
            "dev:live": "vite --mode live"
          },
          "devDependencies": {
            "vite": "^5.0.0"
          }
        }
        """.write(to: projectRoot.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "".write(to: projectRoot.appendingPathComponent("pnpm-lock.yaml"), atomically: true, encoding: .utf8)

        let project = ProjectCommandSnapshotResolver.makeProject(
            name: "workspace",
            path: projectRoot.path,
            type: .devServer
        )

        #expect(project.availableStartupModes.map(\.displayName) == ["默认", "Mock", "Live"])
    }
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectSnapshotMigrationTests
```

Expected: FAIL if the resolver still emits unlabeled or incomplete startup modes.

- [ ] **Step 3: Implement a dedicated startup mode picker and wire it into the two entry points**

Create `Techne/Views/Shared/Components/StartupModePicker.swift`:

```swift
import SwiftUI

struct StartupModePicker: View {
    let modes: [ProjectStartupMode]
    let selectedModeID: String?
    let isDisabled: Bool
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(modes) { mode in
                Button {
                    onSelect(mode.id)
                } label: {
                    if mode.id == selectedModeID {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            Text(currentLabel)
                .font(.system(size: AppConfig.UI.smallFontSize))
                .padding(.horizontal, AppConfig.UI.mediumSpacing)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
        }
        .disabled(isDisabled || modes.count <= 1)
    }

    private var currentLabel: String {
        modes.first(where: { $0.id == selectedModeID })?.displayName ?? "默认"
    }
}
```

Update `Techne/Views/AddProjectSheet.swift` so the preview lists every detected startup mode instead of only the single selected command:

```swift
            if let snapshot = snapshotPreview {
                Divider()
                    .padding(.vertical, AppConfig.UI.smallSpacing)
                Text("可选启动模式")
                    .font(.system(size: AppConfig.UI.smallFontSize, weight: .medium))
                ForEach(snapshot.startupModes) { mode in
                    previewRow(mode.displayName, mode.startCommand)
                }
            }
```

Update `Techne/Views/ProjectCard.swift` so the title row includes the new picker beside the command snapshot badge:

```swift
            if project.type == .devServer, project.availableStartupModes.count > 1 {
                StartupModePicker(
                    modes: project.availableStartupModes,
                    selectedModeID: project.selectedStartupModeID,
                    isDisabled: isTransitioning,
                    onSelect: onSwitchStartupMode
                )
            }
```

Extend `ProjectCard` and `ProjectListView` with the callback:

```swift
    let onSwitchStartupMode: (String) -> Void
```

and:

```swift
                        onSwitchStartupMode: { switchStartupMode(for: project, to: $0) },
```

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectSnapshotMigrationTests
```

Expected: PASS, confirming the mode list and labels are stable enough for the UI to render deterministically.

- [ ] **Step 5: Commit**

```bash
git add Techne/Views/AddProjectSheet.swift Techne/Views/Shared/Components/StartupModePicker.swift Techne/Views/ProjectCard.swift Techne/Views/ProjectListView.swift TechneTests/Models/ProjectSnapshotMigrationTests.swift
git commit -m "feat: expose startup mode selection in project cards"
```

### Task 3: Make startup mode changes durable and restart running projects immediately

**Files:**
- Modify: `Techne/Services/ProjectService.swift`
- Modify: `Techne/Views/ProjectListView.swift`
- Test: `TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift`

- [ ] **Step 1: Write the failing service tests**

Add these tests to `TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift`:

```swift
    @Test
    @MainActor
    func switchingStartupModeWhileStoppedPersistsSelectionWithoutStartingProcess() throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let service = makeProjectService(persistenceRoot: isolatedPersistenceRoot)
        var project = Project(
            name: "frontend-app",
            path: isolatedPersistenceRoot.appendingPathComponent("project").path,
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev",
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "pnpm dev", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "pnpm dev:mock", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )
        service.projects = [project]

        let result = await service.switchStartupMode(for: project, to: "dev:mock")

        guard case .success = result else {
            Issue.record("expected switchStartupMode to succeed")
            return
        }

        let updated = service.projects[0]
        #expect(updated.selectedStartupModeID == "dev:mock")
        #expect(updated.startCommand == "pnpm dev:mock")
        #expect(updated.isRunning == false)
    }

    @Test
    @MainActor
    func switchingStartupModeWhileRunningStopsOldProcessAndStartsNewCommand() async throws {
        let isolatedPersistenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: isolatedPersistenceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedPersistenceRoot) }

        let projectRoot = isolatedPersistenceRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let oldProcess = Process()
        oldProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        oldProcess.arguments = ["30"]
        try oldProcess.run()
        defer {
            if oldProcess.isRunning {
                oldProcess.terminate()
            }
        }

        let service = makeProjectService(persistenceRoot: isolatedPersistenceRoot)
        var project = Project(
            name: "portlens-workspace",
            path: projectRoot.path,
            type: .devServer,
            currentBranch: "main",
            startCommand: "sleep 30",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "",
            stopCommand: ProjectCommandSnapshot.managedStopCommand,
            discardChangesCommand: ProjectCommandSnapshot.defaultDiscardChangesCommand,
            commandProfileName: "自动识别 · Next.js + pnpm",
            installStrategy: .never,
            availableStartupModes: [
                ProjectStartupMode(id: "dev", displayName: "默认", startCommand: "sleep 30", source: .autoDetected),
                ProjectStartupMode(id: "dev:mock", displayName: "Mock", startCommand: "touch mode-switched && sleep 0.2", source: .autoDetected)
            ],
            selectedStartupModeID: "dev"
        )
        project.isRunning = true
        project.runningProcessPID = oldProcess.processIdentifier
        service.projects = [project]

        let result = await service.switchStartupMode(for: project, to: "dev:mock")

        guard case .success = result else {
            Issue.record("expected switchStartupMode to begin restart")
            return
        }

        let restarted = await waitUntil(timeout: .seconds(3)) {
            FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("mode-switched").path)
        }

        #expect(restarted)
        #expect(service.projects[0].selectedStartupModeID == "dev:mock")
        #expect(service.projects[0].startCommand == "touch mode-switched && sleep 0.2")
        #expect(service.projects[0].terminalOutput.contains("[系统] 已切换启动模式为 Mock"))
    }
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectServiceStartupRecoveryTests
```

Expected: FAIL because `ProjectService` does not yet expose `switchStartupMode(for:to:)`.

- [ ] **Step 3: Implement durable mode switching with immediate restart semantics**

Add this API to `Techne/Services/ProjectService.swift`:

```swift
    @MainActor
    func switchStartupMode(for project: Project, to modeID: String) async -> Result<Void, ProjectServiceError> {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return .failure(.pathNotFound(project.path))
        }

        guard projects[index].availableStartupModes.contains(where: { $0.id == modeID }) else {
            return .failure(.invalidConfiguration("无效的启动模式"))
        }

        let wasRunning = projects[index].isRunning || projects[index].runningProcessPID != nil
        projects[index].selectStartupMode(id: modeID)
        let updatedProject = projects[index]
        saveProjects()
        appendSystemTerminalMessage("已切换启动模式为 \(updatedProject.selectedStartupMode?.displayName ?? "默认")", for: updatedProject.id)

        guard wasRunning else {
            return .success(())
        }

        let stopResult = await stopServer(for: updatedProject, cleanCache: false)
        guard case .success = stopResult else {
            appendSystemTerminalMessage("启动模式切换已保存，但停止旧进程失败", for: updatedProject.id)
            return stopResult
        }

        return startServer(for: projects[index])
    }
```

Update `Techne/Views/ProjectListView.swift` with a thin forwarding helper instead of embedding service logic in the view body:

```swift
    private func switchStartupMode(for project: Project, to modeID: String) {
        Task {
            let result = await projectService.switchStartupMode(for: project, to: modeID)
            if case .failure(let error) = result {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
```

Do not call `stopServer(..., cleanCache: true)` during a mode switch. Restarting from `dev` to `dev:mock` is a process-mode transition, not a destructive cache cleanup workflow.

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectServiceStartupRecoveryTests
```

Expected: PASS for stopped-mode persistence and running-mode restart coverage.

- [ ] **Step 5: Commit**

```bash
git add Techne/Services/ProjectService.swift Techne/Views/ProjectListView.swift TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift
git commit -m "feat: restart running projects on startup mode changes"
```

### Task 4: Enforce a singleton main window and route Cmd+1/Cmd+2/Cmd+3 to the existing window

**Files:**
- Create: `Techne/Services/Shared/MainWindowCoordinator.swift`
- Modify: `Techne/TechneApp.swift`
- Modify: `Techne/Views/MenuBarView.swift`
- Modify: `Techne/ContentView.swift`
- Modify: `Techne/AppDelegate.swift`
- Modify: `Techne/Services/Shared/WindowManager.swift`
- Test: `TechneTests/App/MainWindowCoordinatorTests.swift`

- [ ] **Step 1: Write the failing coordinator tests**

Create `TechneTests/App/MainWindowCoordinatorTests.swift`:

```swift
import AppKit
import Testing
@testable import Techne

struct MainWindowCoordinatorTests {
    @Test
    @MainActor
    func reusesExistingMainWindowWithoutRequestingAnotherOpen() {
        let existingWindow = NSWindow()
        existingWindow.identifier = NSUserInterfaceItemIdentifier("main")

        let coordinator = MainWindowCoordinator(
            findWindow: { _ in existingWindow },
            activateApp: { },
            openWindow: { Issue.record("openWindow should not be called") },
            focusWindow: { window in
                #expect(window === existingWindow)
            }
        )

        coordinator.showMainWindow()
    }

    @Test
    @MainActor
    func opensMainWindowWhenNoExistingWindowIsAvailable() {
        var openCount = 0

        let coordinator = MainWindowCoordinator(
            findWindow: { _ in nil },
            activateApp: { },
            openWindow: { openCount += 1 },
            focusWindow: { _ in }
        )

        coordinator.showMainWindow()

        #expect(openCount == 1)
    }
}
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/MainWindowCoordinatorTests
```

Expected: FAIL because `MainWindowCoordinator` does not exist yet.

- [ ] **Step 3: Implement the singleton main-window route**

Create `Techne/Services/Shared/MainWindowCoordinator.swift`:

```swift
import AppKit

@MainActor
struct MainWindowCoordinator {
    let identifier: String
    let findWindow: (String) -> NSWindow?
    let activateApp: () -> Void
    let openWindow: () -> Void
    let focusWindow: (NSWindow) -> Void

    init(
        identifier: String = "main",
        findWindow: @escaping (String) -> NSWindow? = { id in
            NSApp.windows.first(where: { $0.identifier?.rawValue == id })
        },
        activateApp: @escaping () -> Void = {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        },
        openWindow: @escaping () -> Void,
        focusWindow: @escaping (NSWindow) -> Void = { window in
            window.collectionBehavior = [.moveToActiveSpace, .managed, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    ) {
        self.identifier = identifier
        self.findWindow = findWindow
        self.activateApp = activateApp
        self.openWindow = openWindow
        self.focusWindow = focusWindow
    }

    func showMainWindow() {
        activateApp()
        if let window = findWindow(identifier) {
            focusWindow(window)
            return
        }
        openWindow()
    }
}
```

Update `Techne/TechneApp.swift` to replace the multi-instance scene:

```swift
        Window("Techne", id: "main") {
            ContentView(
                commandConfigService: commandConfigService,
                projectService: projectService
            )
            .frame(minWidth: 1080, minHeight: 720)
        }
```

Update `Techne/Views/MenuBarView.swift` so `Cmd+1` / `Cmd+2` / `Cmd+3` ask the coordinator to reuse the existing main window instead of always calling `openWindow(id: "main")` first:

```swift
    private func openAndFocusWindow() {
        MainWindowCoordinator(openWindow: { openWindow(id: "main") }).showMainWindow()
    }
```

Update `Techne/Services/Shared/WindowManager.swift` to delegate to the same focus rules instead of duplicating them:

```swift
    static func showMainWindow(identifier: String = "main") {
        MainWindowCoordinator(
            identifier: identifier,
            openWindow: { }
        ).showMainWindow()
    }
```

Update `Techne/AppDelegate.swift` to restore the singleton main window when the app is reopened from the dock or menu-bar flow:

```swift
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.showMainWindow(identifier: "main")
        return true
    }
```

Keep the existing `NotificationCenter`-based sidebar switching in `ContentView.swift`; the important behavioral change is that the scene itself is singleton and `showMainWindow()` no longer causes a second main window to appear.

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/MainWindowCoordinatorTests
```

Expected: PASS, proving the coordinator reuses an existing main window and only requests `openWindow` when the window is absent.

- [ ] **Step 5: Run the broader regression suite for touched areas**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectSnapshotMigrationTests -only-testing:TechneTests/ProjectServiceStartupRecoveryTests -only-testing:TechneTests/MainWindowCoordinatorTests
```

Expected: PASS for startup mode persistence, restart orchestration, and singleton main-window routing.

- [ ] **Step 6: Commit**

```bash
git add Techne/Services/Shared/MainWindowCoordinator.swift Techne/TechneApp.swift Techne/Views/MenuBarView.swift Techne/ContentView.swift Techne/AppDelegate.swift Techne/Services/Shared/WindowManager.swift TechneTests/App/MainWindowCoordinatorTests.swift
git commit -m "fix: reuse existing main window from menu bar shortcuts"
```
