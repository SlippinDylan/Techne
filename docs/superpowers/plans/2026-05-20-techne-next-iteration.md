# Techne Next Iteration Implementation Plan

> **Historical plan:** This document records the former macOS 15 compatibility baseline. Techne now targets macOS 26.0 or later; do not reintroduce its platform fallback requirements.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add backup and restore, project-level command visibility, optional dependency installation before start, stable browser launch behavior, and manual browser instance launch for the dev server and mini app workflows.

**Architecture:** Move command and startup behavior from loosely coupled templates into project-owned state, then rebuild browser discovery and launch around `NSWorkspace` instead of hard-coded app paths and raw `Process` execution. Keep the current `macOS 15.0` deployment target, but implement modern `SwiftUI` and `AppKit` integration points so the app follows the latest macOS patterns while staying backward compatible.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, FileDocument, NSWorkspace, ServiceManagement, Xcode project target configuration, Swift Testing

---

## Non-Negotiable Engineering Constraints

Implement every task under these constraints:

1. Prefer sustainable design over local patching.
2. Keep ownership boundaries clear between models, services, views, and OS integration code.
3. Do not widen blast radius without a concrete architectural reason.
4. Do not add fallback branches, duplicated code paths, or compatibility shims unless they are required for data migration or platform compatibility.
5. Do not “make it compile” by adding ad hoc flags, sentinel state, fragile delays, or UI-condition hacks without first fixing the underlying ownership or lifecycle problem.
6. Keep changes cohesive and reversible. Each task should leave the codebase in a cleaner state than before it started.
7. Prefer moving logic into typed models or focused services over embedding behavior in view callbacks or long shell-string composition.
8. If an implementation choice would trade long-term maintainability for short-term speed, stop and choose the maintainable design.

## Architectural Guardrails

Apply these guardrails throughout execution:

- Keep browser discovery separate from browser launch, and browser launch separate from browser instance tracking.
- Keep backup document format and import behavior versioned and explicit.
- Keep project-owned command snapshots authoritative at runtime; treat command templates as seed data, not runtime truth.
- Keep startup orchestration centralized; do not split dependency installation behavior across multiple unrelated services.
- Keep UI presentation state in views, but keep decision-making and side effects in services or typed coordinators.
- Keep data migration code explicit and easy to delete after the transition window is over.

## Stop Conditions

Stop and redesign before continuing if any task drifts into one of these failure modes:

- The same business rule is being implemented in more than one place.
- A view starts owning process orchestration, persistence logic, or migration behavior.
- A service begins to depend on incidental UI state to behave correctly.
- A new feature is being implemented by branching the old path instead of replacing it with a single coherent path.
- A fix depends on arbitrary sleep timing where a lifecycle signal, callback, or state transition should exist.
- A change introduces hidden coupling that will make later tasks harder.

## Definition of Done

The iteration is not done when the app merely compiles or when the visible feature appears to work once. It is done only when all of the following are true:

### Functional completion

- Backup export works from settings and produces a valid portable backup file.
- Backup import restores managed projects and command configurations without corrupting existing local state.
- Project cards in `开发服务与实例` and `微信小程序构建` show project-level command details through a stable UI affordance.
- Starting a project can optionally install dependencies first according to the configured install strategy.
- Browser selection shows only actually installed browsers.
- Browser instance launch is reliable across all supported launch entry points.
- Manual browser instance launch works with and without a URL.

### Architectural completion

- There is exactly one coherent launch path per browser-launch scenario, not multiple diverging implementations.
- Browser discovery, browser launch, and browser instance tracking have clear responsibility boundaries.
- Project runtime command behavior is driven by project-owned command snapshots, not scattered template lookups at arbitrary runtime call sites.
- Startup orchestration is centralized and does not require duplicating install/start decision logic across services.
- Settings UI triggers backup workflows, but does not own backup business logic.
- Migration logic for old persisted data is explicit, minimal, and isolated to decoding or import boundaries.

### Code quality completion

- No task leaves behind temporary compatibility hacks that the next task depends on.
- No new behavior is implemented by copying and editing similar code in multiple files when a shared abstraction should exist.
- No view becomes a side-effect coordinator for process launch, persistence, migration, or OS-integration behavior.
- No implementation relies on arbitrary sleep timing where a signal-driven or callback-driven design is available.
- New types and services introduced in this plan have names, ownership, and responsibilities that are obvious from the code.

### Verification completion

- All tests introduced by this plan pass.
- Existing app build remains green for the main target.
- Manual verification has been performed for:
  - one dev server project
  - one mini app project
  - one Chromium-family browser
  - Safari
  - backup export/import flow
  - manual browser instance launch with URL
  - manual browser instance launch without URL
- The plan document checkboxes are updated to reflect actual completion state.

### Maintainability completion

- A future engineer can find the source of truth for backup, startup orchestration, and browser launch behavior without tracing through multiple partial implementations.
- The final implementation reduces, or at minimum does not increase, accidental complexity relative to the current codebase.
- If a design tradeoff was required, it is visible in the code structure and explained in commit history or task notes, not hidden in ad hoc branching logic.

## Closure Task: Command Surface Consolidation And Snapshot Cleanup

**Intent:** Finish the command-model migration as a product-level closure task. Remove the leaked `命令配置` module from user-visible flows, keep project command capability intact, and re-establish `Project` snapshots as the only runtime source of truth for command details.

### Scope

- Remove the user-visible `命令配置` module entry points from the main app shell and menu bar.
- Remove `AddProjectSheet` dependency on `CommandConfigService` and stop rendering template cards or snapshot-config garbage in project creation.
- Introduce a single stable default-command policy for supported project types so newly added projects receive a complete project-owned command snapshot.
- Add idempotent project/config migration that:
  - removes persisted temp-directory projects under `/var/folders/.../T/...`
  - removes related `Snapshot Config ...` garbage configs
  - stops auto-seeding default command configs into empty storage
- Repair legacy real projects by backfilling only missing command snapshot fields from a single deterministic policy, without overriding existing valid commands.
- Add an explicit `新建浏览器实例` entry point inside `开发服务与实例` and route it through the existing browser launch flow.

### Non-Goals / Boundaries

- Do not delete project command capability.
- Do not delete valid command information already owned by real projects.
- Do not rewrite the entire add-project flow.
- Do not keep dual-track UI where the legacy command-config surface is merely hidden for later cleanup.
- Do not add view-level template lookup as a fallback for command detail rendering.
- Do not clean or revert unrelated dirty worktree files, including `AppIcon`, `.deriveddata`, and unrelated `docs/superpowers` content.

### Source Of Truth Rules

- Runtime command execution and command detail display must read from `Project` snapshot fields only.
- Default command inference must be defined in one maintainable boundary, not scattered across views and services.
- Legacy `CommandConfig` support, if retained internally, is migration-only and must not remain a primary UI or product workflow.
- Browser manual-launch UI must reuse the current browser detection, launch, tracking, and persistence boundaries rather than creating a second launch stack.

### Required Automated Verification

- Failing tests must be added first, then implementation, then green re-runs.
- Coverage must include:
  - empty persistence no longer auto-seeds default command configs
  - startup load removes temp-directory projects
  - startup load removes invalid snapshot configs
  - new projects receive a complete project-owned command snapshot
  - legacy projects with broken `commandConfigId` still backfill to a complete snapshot
  - legacy projects with valid existing commands only fill empty fields
  - command details remain project-snapshot-only
  - existing browser tests still pass
- Final verification must include targeted tests plus one app build.

### Closure Definition of Done

- Users cannot see a `命令配置` module entry in the sidebar or menu bar.
- Adding a project no longer shows command-config template cards or snapshot-config junk.
- Project command capability still exists and remains available from project-owned snapshots.
- Newly added projects always persist a complete command snapshot.
- Persisted temp projects under `/var/folders/.../T/...` no longer appear in the app.
- Snapshot-config garbage is removed and no longer re-generated on empty storage.
- Real project command-detail popovers no longer degrade into mostly empty fields.
- `开发服务与实例` exposes a clear, visible `新建浏览器实例` entry point.
- Automated tests pass.
- `xcodebuild` build passes.
- Unrelated dirty worktree files remain untouched.
- No push is performed.

### Task 1: Add a test target and a typed backup document foundation

**Files:**
- Create: `TechneTests/Backup/TechneBackupDocumentTests.swift`
- Create: `TechneTests/Models/ProjectSnapshotMigrationTests.swift`
- Create: `Techne/Models/Backup/TechneBackupPayload.swift`
- Create: `Techne/Models/Backup/TechneBackupDocument.swift`
- Modify: `Techne.xcodeproj/project.pbxproj`
- Modify: `Techne/Models/Project.swift`

- [x] **Step 1: Create the test target folder structure and add the test target entries**

Create these folders on disk:

```text
TechneTests/
TechneTests/Backup/
TechneTests/Models/
```

Add a `TechneTests` macOS unit test target to `Techne.xcodeproj/project.pbxproj` with Swift Testing enabled and source membership for the two new test files.

- [x] **Step 2: Write the failing backup document round-trip test**

Create `TechneTests/Backup/TechneBackupDocumentTests.swift`:

```swift
import Foundation
import Testing
@testable import Techne

struct TechneBackupDocumentTests {
    @Test
    func backupDocumentRoundTripsProjectsAndConfigs() throws {
        let payload = TechneBackupPayload(
            schemaVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_715_768_000),
            appVersion: "1.0.0",
            projects: [
                Project(
                    name: "frontend-app",
                    path: "/tmp/frontend-app",
                    type: .devServer,
                    currentBranch: "main",
                    startCommand: "pnpm dev",
                    buildCommand: "pnpm build",
                    cleanCommand: "rm -rf dist",
                    installCommand: "pnpm install",
                    stopCommand: "",
                    discardChangesCommand: "git restore . && git clean -fd",
                    commandProfileName: "Vite + pnpm",
                    installStrategy: .ifMissing
                )
            ],
            commandConfigs: [
                CommandConfig(
                    name: "Vite + pnpm",
                    projectType: .devServer,
                    startCommand: "pnpm dev",
                    buildCommand: "pnpm build",
                    cleanCommand: "rm -rf dist",
                    discardChangesCommand: "git reset --hard && git clean -fd",
                    installCommand: "pnpm install",
                    stopCommand: ""
                )
            ]
        )

        let document = TechneBackupDocument(payload: payload)
        let wrapper = try document.fileWrapper(configuration: .init())
        let restored = try TechneBackupDocument(
            configuration: .init(file: wrapper, contentType: .json)
        )

        #expect(restored.payload.projects.count == 1)
        #expect(restored.payload.commandConfigs.count == 1)
        #expect(restored.payload.projects[0].installStrategy == .ifMissing)
        #expect(restored.payload.projects[0].commandProfileName == "Vite + pnpm")
    }
}
```

- [x] **Step 3: Write the failing legacy project migration test**

Create `TechneTests/Models/ProjectSnapshotMigrationTests.swift`:

```swift
import Foundation
import Testing
@testable import Techne

struct ProjectSnapshotMigrationTests {
    @Test
    func legacyProjectDecodesWithDefaultCommandSnapshot() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-app",
          "path": "/tmp/legacy-app",
          "type": "开发服务与实例",
          "currentBranch": "main",
          "startCommand": "pnpm dev",
          "addedDate": 0
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(Project.self, from: json)

        #expect(project.startCommand == "pnpm dev")
        #expect(project.buildCommand == "")
        #expect(project.installCommand == "")
        #expect(project.commandProfileName == nil)
        #expect(project.installStrategy == .ifMissing)
    }
}
```

- [x] **Step 4: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/TechneBackupDocumentTests -only-testing:TechneTests/ProjectSnapshotMigrationTests
```

Expected: build or test failure because `TechneBackupPayload`, `TechneBackupDocument`, `InstallStrategy`, and the new `Project` fields do not exist yet.

- [x] **Step 5: Implement the minimal backup models and project snapshot fields**

Create `Techne/Models/Backup/TechneBackupPayload.swift`:

```swift
import Foundation

struct TechneBackupPayload: Codable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var projects: [Project]
    var commandConfigs: [CommandConfig]
}
```

Create `Techne/Models/Backup/TechneBackupDocument.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct TechneBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var payload: TechneBackupPayload

    init(payload: TechneBackupPayload) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        payload = try JSONDecoder().decode(TechneBackupPayload.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return .init(regularFileWithContents: data)
    }
}
```

Update `Techne/Models/Project.swift` to add:

```swift
enum InstallStrategy: String, Codable, Sendable {
    case never
    case ifMissing
    case always
}
```

and persist these new fields on `Project`:

```swift
var buildCommand: String
var cleanCommand: String
var installCommand: String
var stopCommand: String
var discardChangesCommand: String
var commandProfileName: String?
var installStrategy: InstallStrategy
```

Use backward-compatible decoding with defaults:

```swift
self.buildCommand = try container.decodeIfPresent(String.self, forKey: .buildCommand) ?? ""
self.cleanCommand = try container.decodeIfPresent(String.self, forKey: .cleanCommand) ?? ""
self.installCommand = try container.decodeIfPresent(String.self, forKey: .installCommand) ?? ""
self.stopCommand = try container.decodeIfPresent(String.self, forKey: .stopCommand) ?? ""
self.discardChangesCommand = try container.decodeIfPresent(String.self, forKey: .discardChangesCommand) ?? ""
self.commandProfileName = try container.decodeIfPresent(String.self, forKey: .commandProfileName)
self.installStrategy = try container.decodeIfPresent(InstallStrategy.self, forKey: .installStrategy) ?? .ifMissing
```

- [x] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/TechneBackupDocumentTests -only-testing:TechneTests/ProjectSnapshotMigrationTests
```

Expected: PASS

- [x] **Step 7: Commit**

```bash
git add Techne.xcodeproj/project.pbxproj Techne/Models/Backup/TechneBackupPayload.swift Techne/Models/Backup/TechneBackupDocument.swift Techne/Models/Project.swift TechneTests/Backup/TechneBackupDocumentTests.swift TechneTests/Models/ProjectSnapshotMigrationTests.swift
git commit -m "feat: add backup document foundation and project command snapshot model"
```

### Task 2: Add backup export and import to settings

**Files:**
- Create: `Techne/Services/BackupService.swift`
- Modify: `Techne/ContentView.swift`
- Modify: `Techne/Services/ProjectService.swift`
- Modify: `Techne/Services/CommandConfigService.swift`
- Test: `TechneTests/Backup/BackupServiceMergeTests.swift`

- [x] **Step 1: Write the failing merge import test**

Create `TechneTests/Backup/BackupServiceMergeTests.swift`:

```swift
import Foundation
import Testing
@testable import Techne

struct BackupServiceMergeTests {
    @Test
    func mergeImportSkipsDuplicateProjectPaths() {
        let existing = [
            Project(
                name: "frontend-app",
                path: "/tmp/frontend-app",
                type: .devServer,
                currentBranch: "main",
                startCommand: "pnpm dev",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "pnpm install",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing
            )
        ]

        let incoming = existing + [
            Project(
                name: "mini-program",
                path: "/tmp/mini-program",
                type: .miniApp,
                currentBranch: "main",
                startCommand: "pnpm dev:mp-weixin",
                buildCommand: "",
                cleanCommand: "",
                installCommand: "pnpm install",
                stopCommand: "",
                discardChangesCommand: "",
                commandProfileName: nil,
                installStrategy: .ifMissing
            )
        ]

        let merged = BackupService.mergeProjects(existing: existing, incoming: incoming)
        #expect(merged.count == 2)
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/BackupServiceMergeTests
```

Expected: FAIL because `BackupService` does not exist.

- [x] **Step 3: Implement the backup service**

Create `Techne/Services/BackupService.swift`:

```swift
import AppKit
import Foundation

@MainActor
final class BackupService {
    static func mergeProjects(existing: [Project], incoming: [Project]) -> [Project] {
        var seen = Set(existing.map { normalizePath($0.path) })
        var merged = existing

        for project in incoming {
            let normalized = normalizePath(project.path)
            guard !seen.contains(normalized) else { continue }
            merged.append(project)
            seen.insert(normalized)
        }

        return merged
    }

    static func mergeConfigs(existing: [CommandConfig], incoming: [CommandConfig]) -> [CommandConfig] {
        var seen = Set(existing.map(\.name))
        var merged = existing

        for config in incoming where !seen.contains(config.name) {
            merged.append(config)
            seen.insert(config.name)
        }

        return merged
    }

    static func makePayload(projects: [Project], commandConfigs: [CommandConfig], appVersion: String) -> TechneBackupPayload {
        TechneBackupPayload(
            schemaVersion: 1,
            exportedAt: Date(),
            appVersion: appVersion,
            projects: projects,
            commandConfigs: commandConfigs
        )
    }

    static func revealAppSupportDirectory(at url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
```

- [x] **Step 4: Expose import/export hooks from services**

Add these methods to `Techne/Services/ProjectService.swift`:

```swift
@MainActor
func replaceProjectsForImport(_ projects: [Project]) {
    self.projects = projects
    saveProjects()
    setupMonitorsForAllProjects()
    refreshAll()
}
```

```swift
@MainActor
func mergeImportedProjects(_ imported: [Project]) {
    projects = BackupService.mergeProjects(existing: projects, incoming: imported)
    saveProjects()
    setupMonitorsForAllProjects()
    refreshAll()
}
```

Add these methods to `Techne/Services/CommandConfigService.swift`:

```swift
func replaceConfigsForImport(_ configs: [CommandConfig]) {
    self.configs = configs
    saveConfigs()
}
```

```swift
func mergeImportedConfigs(_ configs: [CommandConfig]) {
    self.configs = BackupService.mergeConfigs(existing: self.configs, incoming: configs)
    saveConfigs()
}
```

- [x] **Step 5: Add settings export and import UI**

Extend `MainSettingsView` in `Techne/ContentView.swift` with state:

```swift
@Environment(ProjectService.self) private var projectService
@Environment(CommandConfigService.self) private var commandConfigService
@State private var exportingBackup = false
@State private var importingBackup = false
@State private var backupDocument = TechneBackupDocument(
    payload: .init(schemaVersion: 1, exportedAt: .now, appVersion: "1.0.0", projects: [], commandConfigs: [])
)
```

Add a `数据与备份` section:

```swift
GroupBox(label: Label("数据与备份", systemImage: "externaldrive")) {
    VStack(alignment: .leading, spacing: 12) {
        Button("导出备份") {
            backupDocument = TechneBackupDocument(
                payload: BackupService.makePayload(
                    projects: projectService.projects,
                    commandConfigs: commandConfigService.configs,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                )
            )
            exportingBackup = true
        }

        Button("导入备份") {
            importingBackup = true
        }

        Button("打开数据目录") {
            let url = PersistenceService<Project>(filename: "projects.json").storageURL.deletingLastPathComponent()
            BackupService.revealAppSupportDirectory(at: url)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```

Attach modifiers:

```swift
.fileExporter(
    isPresented: $exportingBackup,
    document: backupDocument,
    contentType: .json,
    defaultFilename: "techne-backup"
) { _ in }
.fileImporter(
    isPresented: $importingBackup,
    allowedContentTypes: [.json],
    allowsMultipleSelection: false
) { result in
    guard case .success(let urls) = result, let url = urls.first else { return }
    guard let data = try? Data(contentsOf: url),
          let payload = try? JSONDecoder().decode(TechneBackupPayload.self, from: data) else { return }

    commandConfigService.mergeImportedConfigs(payload.commandConfigs)
    projectService.mergeImportedProjects(payload.projects)
}
```

- [x] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/BackupServiceMergeTests
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Techne/Services/BackupService.swift Techne/ContentView.swift Techne/Services/ProjectService.swift Techne/Services/CommandConfigService.swift TechneTests/Backup/BackupServiceMergeTests.swift
git commit -m "feat: add backup export and import settings flow"
```

### Task 3: Move command visibility into project cards and project creation

**Files:**
- Create: `Techne/Views/ProjectCommandDetailsPopover.swift`
- Modify: `Techne/Views/ProjectCard.swift`
- Modify: `Techne/Views/AddProjectSheet.swift`
- Modify: `Techne/Services/ProjectService.swift`
- Test: `TechneTests/Models/ProjectCommandSnapshotTests.swift`

- [ ] **Step 1: Write the failing project command snapshot test**

Create `TechneTests/Models/ProjectCommandSnapshotTests.swift`:

```swift
import Testing
@testable import Techne

struct ProjectCommandSnapshotTests {
    @Test
    func addProjectCopiesSelectedConfigIntoProjectSnapshot() async throws {
        let configService = CommandConfigService()
        let config = CommandConfig(
            name: "Snapshot Config",
            projectType: .devServer,
            startCommand: "pnpm dev",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist",
            discardChangesCommand: "git restore . && git clean -fd",
            installCommand: "pnpm install",
            stopCommand: "pkill -f vite"
        )
        _ = configService.addConfig(config)

        let service = await ProjectService(commandConfigService: configService)
        let result = await MainActor.run {
            service.addProject(path: "/tmp/project", type: .devServer, configId: config.id)
        }

        guard case .success(let project) = result else {
            Issue.record("expected project creation success")
            return
        }

        #expect(project.buildCommand == "pnpm build")
        #expect(project.cleanCommand == "rm -rf dist")
        #expect(project.installCommand == "pnpm install")
        #expect(project.commandProfileName == "Snapshot Config")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectCommandSnapshotTests
```

Expected: FAIL because `addProject` still only copies `startCommand`.

- [ ] **Step 3: Copy command snapshots into projects on add**

Update `ProjectService.addProject(...)` in `Techne/Services/ProjectService.swift` so the selected config populates the full project snapshot:

```swift
let selectedConfig = configId.flatMap { commandConfigService.getConfig(by: $0) }
let project = Project(
    name: projectName,
    path: path,
    type: type,
    currentBranch: "",
    startCommand: selectedConfig?.startCommand ?? type.defaultStartCommand,
    buildCommand: selectedConfig?.buildCommand ?? "",
    cleanCommand: selectedConfig?.cleanCommand ?? "",
    installCommand: selectedConfig?.installCommand ?? "",
    stopCommand: selectedConfig?.stopCommand ?? "",
    discardChangesCommand: selectedConfig?.discardChangesCommand ?? "",
    commandProfileName: selectedConfig?.name,
    installStrategy: .ifMissing,
    commandConfigId: configId
)
```

- [ ] **Step 4: Add the command details popover**

Create `Techne/Views/ProjectCommandDetailsPopover.swift`:

```swift
import SwiftUI

struct ProjectCommandDetailsPopover: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project.commandProfileName ?? "自定义命令")
                .font(.headline)

            commandRow("启动", project.startCommand)
            commandRow("安装依赖", project.installCommand)
            commandRow("构建", project.buildCommand)
            commandRow("清理", project.cleanCommand)
            commandRow("停止", project.stopCommand)
            commandRow("丢弃更改", project.discardChangesCommand)
            commandRow("安装策略", project.installStrategy.rawValue)
        }
        .padding(16)
        .frame(width: 420)
    }

    private func commandRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "未配置" : value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 5: Add the tag and popover to project cards**

In `Techne/Views/ProjectCard.swift`, add state:

```swift
@State private var showingCommandDetails = false
```

Add this tag beside the project title:

```swift
Button(project.commandProfileName ?? "自定义命令") {
    showingCommandDetails = true
}
.font(.system(size: AppConfig.UI.smallFontSize))
.padding(.horizontal, AppConfig.UI.mediumSpacing)
.padding(.vertical, 2)
.background(.secondary.opacity(0.12))
.clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.smallCornerRadius))
.buttonStyle(.plain)
.popover(isPresented: $showingCommandDetails) {
    ProjectCommandDetailsPopover(project: project)
}
```

Update `AddProjectSheet` empty state copy from:

```swift
Text("请先在命令配置页面创建配置")
```

to:

```swift
Text("可以先直接添加项目，后续在项目卡片中查看或调整命令详情")
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectCommandSnapshotTests
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Techne/Services/ProjectService.swift Techne/Views/ProjectCard.swift Techne/Views/ProjectCommandDetailsPopover.swift Techne/Views/AddProjectSheet.swift TechneTests/Models/ProjectCommandSnapshotTests.swift
git commit -m "feat: show project command details from project-owned snapshots"
```

### Task 4: Add optional dependency installation before start

**Files:**
- Create: `Techne/Services/ProjectStartupCoordinator.swift`
- Modify: `Techne/Services/ProjectService.swift`
- Modify: `Techne/Services/Shared/ProcessManager.swift`
- Modify: `Techne/Models/Project.swift`
- Test: `TechneTests/Startup/ProjectStartupCoordinatorTests.swift`

- [ ] **Step 1: Write the failing startup coordinator test**

Create `TechneTests/Startup/ProjectStartupCoordinatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Techne

struct ProjectStartupCoordinatorTests {
    @Test
    func shouldInstallWhenStrategyIsIfMissingAndNodeModulesDoesNotExist() {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? "{}".write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let project = Project(
            name: "frontend-app",
            path: root.path,
            type: .devServer,
            currentBranch: "main",
            startCommand: "pnpm dev",
            buildCommand: "",
            cleanCommand: "",
            installCommand: "pnpm install",
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: nil,
            installStrategy: .ifMissing
        )

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectStartupCoordinatorTests
```

Expected: FAIL because `ProjectStartupCoordinator` does not exist.

- [ ] **Step 3: Implement the startup coordinator**

Create `Techne/Services/ProjectStartupCoordinator.swift`:

```swift
import Foundation

enum StartupPhase: Sendable {
    case installing
    case cleaning
    case starting
}

enum StartupExecutionPlan: Sendable {
    case installThenStart
    case startOnly
}

struct ProjectStartupCoordinator {
    static func shouldInstallDependencies(for project: Project) -> Bool {
        guard !project.installCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch project.installStrategy {
        case .never:
            return false
        case .always:
            return true
        case .ifMissing:
            let root = URL(fileURLWithPath: project.path)
            let packageJSON = root.appendingPathComponent("package.json").path
            let nodeModules = root.appendingPathComponent("node_modules").path
            return FileManager.default.fileExists(atPath: packageJSON) && !FileManager.default.fileExists(atPath: nodeModules)
        }
    }
}
```

- [ ] **Step 4: Route project start through the coordinator**

In `ProjectService.startServer(for:)`, replace direct start execution with:

```swift
switch project.type {
case .devServer:
    return startProjectThroughCoordinator(project, category: category, streamsOutput: false)
case .miniApp:
    return startProjectThroughCoordinator(project, category: category, streamsOutput: true)
}
```

Implement `startProjectThroughCoordinator` so it builds the shell script in this order:

```swift
source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || source ~/.bashrc 2>/dev/null
cd <project-path>
<optional installCommand>
<optional cleanCommand>
<startCommand>
```

When install is needed, prepend visible log lines:

```text
[系统] 正在检查依赖...
[系统] 检测到缺少依赖，准备执行安装命令: pnpm install
```

- [ ] **Step 5: Add a dedicated transition state**

Extend `ProjectTransitionState` in `Techne/Models/Project.swift`:

```swift
case installing
```

Update `ProjectCard.transitionStatusLabel`:

```swift
case .installing:
    return "安装中"
```

Ensure `ProjectService` sets `.installing` before running the install command and returns to `.idle` after a successful start or terminal failure.

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ProjectStartupCoordinatorTests
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Techne/Services/ProjectStartupCoordinator.swift Techne/Services/ProjectService.swift Techne/Services/Shared/ProcessManager.swift Techne/Models/Project.swift TechneTests/Startup/ProjectStartupCoordinatorTests.swift
git commit -m "feat: install dependencies before start when required"
```

### Task 5: Rebuild browser discovery and stable launch behavior

**Files:**
- Create: `Techne/Models/BrowserLaunchRequest.swift`
- Modify: `Techne/Models/Browser.swift`
- Modify: `Techne/Services/BrowserDetectionService.swift`
- Modify: `Techne/Services/BrowserLaunchService.swift`
- Modify: `Techne/Services/ChromeDetectionService.swift`
- Modify: `Techne/Views/ProjectCard.swift`
- Modify: `Techne/Views/DevEnvironment/Components/Cards/ServerCardWithInstances.swift`
- Modify: `Techne/Views/DevEnvironment/Components/Cards/DiscoveredServerCard.swift`
- Modify: `Techne/Views/DevEnvironment/Components/Sheets/BrowserSelectorSheet.swift`
- Test: `TechneTests/Browser/BrowserDetectionServiceTests.swift`

- [ ] **Step 1: Write the failing browser discovery test**

Create `TechneTests/Browser/BrowserDetectionServiceTests.swift`:

```swift
import Testing
@testable import Techne

struct BrowserDetectionServiceTests {
    @Test
    func supportedBrowserCatalogUsesBundleIdentifiers() {
        let browsers = BrowserType.allCases
        #expect(browsers.contains(.chrome))
        #expect(BrowserType.chrome.bundleId == "com.google.Chrome")
        #expect(BrowserType.safari.bundleId == "com.apple.Safari")
    }
}
```

- [ ] **Step 2: Run the test to verify the current browser design still needs changes**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/BrowserDetectionServiceTests
```

Expected: PASS for the catalog basics, but the manual code review at this step should confirm that installed browser detection still depends on hard-coded executable paths and not `NSWorkspace`.

- [ ] **Step 3: Introduce a launch request model**

Create `Techne/Models/BrowserLaunchRequest.swift`:

```swift
import Foundation

struct BrowserLaunchRequest: Sendable {
    var browser: Browser
    var url: String?
    var profileDirectoryName: String
    var opensInNewInstance: Bool
    var debugPort: Int?
    var tracksInstance: Bool
    var launchSource: String
}
```

- [ ] **Step 4: Replace hard-coded browser executable lookup with NSWorkspace lookup**

In `Techne/Models/Browser.swift`, change `Browser` to store `appURL` instead of a raw executable path:

```swift
struct Browser: Identifiable, Hashable {
    let type: BrowserType
    let appURL: URL
    let isDefault: Bool

    var id: String { "\(type.bundleId)_\(appURL.path)" }
    var displayName: String { isDefault ? "\(type.rawValue) (默认)" : type.rawValue }
    var appIcon: NSImage? { NSWorkspace.shared.icon(forFile: appURL.path) }
}
```

In `BrowserDetectionService`, replace path searching with:

```swift
func detectInstalledBrowsers() -> [Browser] {
    let defaultBundleId = getDefaultBrowserBundleId()
    return BrowserType.allCases.compactMap { type in
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: type.bundleId) else {
            return nil
        }
        return Browser(type: type, appURL: appURL, isDefault: type.bundleId == defaultBundleId)
    }
    .sorted { lhs, rhs in
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
        return lhs.displayName < rhs.displayName
    }
}
```

- [ ] **Step 5: Replace browser launching with NSWorkspace.OpenConfiguration**

In `BrowserLaunchService`, replace `launchBrowser(browserPath:url:debugPort:)` with:

```swift
func launchBrowser(_ request: BrowserLaunchRequest) async -> Result<NSRunningApplication, Error>
```

Launch Chromium-family browsers using:

```swift
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.createsNewApplicationInstance = request.opensInNewInstance
configuration.arguments = [
    "--user-data-dir=\(profileDir)"
] + (request.debugPort.map { ["--remote-debugging-port=\($0)"] } ?? []) + [
    "--no-first-run",
    "--no-default-browser-check"
] + (request.url.map { [$0] } ?? [])
```

Then:

```swift
return await withCheckedContinuation { continuation in
    NSWorkspace.shared.openApplication(at: request.browser.appURL, configuration: configuration) { app, error in
        if let error {
            continuation.resume(returning: .failure(error))
        } else if let app {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            continuation.resume(returning: .success(app))
        } else {
            continuation.resume(returning: .failure(CocoaError(.fileNoSuchFile)))
        }
    }
}
```

- [ ] **Step 6: Unify all browser entry points on the new launch request**

Update these call sites to build the same request shape:

- `Techne/Views/ProjectCard.swift`
- `Techne/Views/DevEnvironment/Components/Cards/ServerCardWithInstances.swift`
- `Techne/Views/DevEnvironment/Components/Cards/DiscoveredServerCard.swift`

For attached dev-server launches, use:

```swift
let request = BrowserLaunchRequest(
    browser: browser,
    url: "http://localhost:\(port)",
    profileDirectoryName: "dev-server-\(port)-\(Int(Date().timeIntervalSince1970))",
    opensInNewInstance: true,
    debugPort: debugPort,
    tracksInstance: browser.type != .safari,
    launchSource: "dev-server"
)
```

After success, always post:

```swift
NotificationCenter.default.post(name: .browserDidOpen, object: nil)
```

- [ ] **Step 7: Make browser selector support optional URL copy**

In `BrowserSelectorSheet.swift`, change:

```swift
let url: String
```

to:

```swift
let url: String?
```

and update the header copy:

```swift
Text(url.map { "打开 \($0)" } ?? "启动独立浏览器实例")
```

- [ ] **Step 8: Run focused verification**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/BrowserDetectionServiceTests
```

Then run the app manually and verify:

```bash
xcodebuild -scheme Techne -destination 'platform=macOS' build
```

Expected:
- browser picker shows only installed browsers
- one click opens one window
- browser instances refresh without restarting the app

- [ ] **Step 9: Commit**

```bash
git add Techne/Models/BrowserLaunchRequest.swift Techne/Models/Browser.swift Techne/Services/BrowserDetectionService.swift Techne/Services/BrowserLaunchService.swift Techne/Services/ChromeDetectionService.swift Techne/Views/ProjectCard.swift Techne/Views/DevEnvironment/Components/Cards/ServerCardWithInstances.swift Techne/Views/DevEnvironment/Components/Cards/DiscoveredServerCard.swift Techne/Views/DevEnvironment/Components/Sheets/BrowserSelectorSheet.swift TechneTests/Browser/BrowserDetectionServiceTests.swift
git commit -m "feat: stabilize browser discovery and launch flows"
```

### Task 6: Add manual browser instance launch

**Files:**
- Create: `Techne/Views/ManualBrowserLaunchSheet.swift`
- Modify: `Techne/Views/ProjectListView.swift`
- Modify: `Techne/Services/ChromeDetectionService.swift`
- Test: `TechneTests/Browser/ManualBrowserLaunchRequestTests.swift`

- [ ] **Step 1: Write the failing manual launch request test**

Create `TechneTests/Browser/ManualBrowserLaunchRequestTests.swift`:

```swift
import Testing
@testable import Techne

struct ManualBrowserLaunchRequestTests {
    @Test
    func manualLaunchRequestAllowsEmptyURL() {
        let browser = Browser(
            type: .chrome,
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isDefault: false
        )

        let request = BrowserLaunchRequest(
            browser: browser,
            url: nil,
            profileDirectoryName: "manual-preview",
            opensInNewInstance: true,
            debugPort: 9333,
            tracksInstance: true,
            launchSource: "manual"
        )

        #expect(request.url == nil)
        #expect(request.launchSource == "manual")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ManualBrowserLaunchRequestTests
```

Expected: FAIL until the new launch model is present and compiled in the test target.

- [ ] **Step 3: Add the manual browser launch sheet**

Create `Techne/Views/ManualBrowserLaunchSheet.swift`:

```swift
import SwiftUI

struct ManualBrowserLaunchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let browsers: [Browser]
    let onLaunch: (BrowserLaunchRequest) -> Void

    @State private var selectedBrowserID: String?
    @State private var url = ""
    @State private var profileDirectoryName = "chrome-frontend-preview"
    @State private var enableDebugPort = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("启动独立浏览器实例")
                .font(.title3.weight(.semibold))

            Picker("浏览器", selection: $selectedBrowserID) {
                ForEach(browsers) { browser in
                    Text(browser.displayName).tag(Optional(browser.id))
                }
            }

            TextField("可选地址，例如 http://localhost:5173", text: $url)
            TextField("Profile 名称", text: $profileDirectoryName)
            Toggle("启用远程调试端口", isOn: $enableDebugPort)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("启动") {
                    guard let browser = browsers.first(where: { $0.id == selectedBrowserID }) else { return }
                    onLaunch(
                        BrowserLaunchRequest(
                            browser: browser,
                            url: url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : url,
                            profileDirectoryName: profileDirectoryName,
                            opensInNewInstance: true,
                            debugPort: enableDebugPort ? AppConfig.Browser.defaultDebugPort : nil,
                            tracksInstance: browser.type != .safari,
                            launchSource: "manual"
                        )
                    )
                    dismiss()
                }
                .disabled(selectedBrowserID == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            selectedBrowserID = selectedBrowserID ?? browsers.first?.id
        }
    }
}
```

- [ ] **Step 4: Add the sheet entry point to the dev server page**

In `ProjectListView.swift`, add state:

```swift
@State private var showingManualBrowserLaunch = false
@State private var installedBrowsers: [Browser] = []
```

Add a toolbar button for `projectType == .devServer`:

```swift
Button(action: {
    installedBrowsers = BrowserDetectionService().detectInstalledBrowsers()
    showingManualBrowserLaunch = true
}) {
    Image(systemName: "globe.badge.chevron.backward")
}
.adaptiveGlassButtonStyle()
.help("启动独立浏览器实例")
```

Attach sheet:

```swift
.sheet(isPresented: $showingManualBrowserLaunch) {
    ManualBrowserLaunchSheet(browsers: installedBrowsers) { request in
        Task {
            let launchService = BrowserLaunchService()
            let finalRequest = BrowserLaunchRequest(
                browser: request.browser,
                url: request.url,
                profileDirectoryName: request.profileDirectoryName,
                opensInNewInstance: request.opensInNewInstance,
                debugPort: request.debugPort ?? launchService.findAvailablePort(startingFrom: AppConfig.Browser.defaultDebugPort),
                tracksInstance: request.tracksInstance,
                launchSource: request.launchSource
            )
            _ = await launchService.launchBrowser(finalRequest)
            NotificationCenter.default.post(name: .browserDidOpen, object: nil)
        }
    }
}
```

- [ ] **Step 5: Run the tests and manual verification**

Run:

```bash
xcodebuild test -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/ManualBrowserLaunchRequestTests
```

Then verify manually:

```bash
xcodebuild -scheme Techne -destination 'platform=macOS' build
```

Expected:
- empty URL launches a clean browser instance
- provided URL launches that page
- launched instance appears in the browser instance list

- [ ] **Step 6: Commit**

```bash
git add Techne/Views/ManualBrowserLaunchSheet.swift Techne/Views/ProjectListView.swift Techne/Services/ChromeDetectionService.swift TechneTests/Browser/ManualBrowserLaunchRequestTests.swift
git commit -m "feat: add manual browser instance launch"
```

## Self-Review

1. **Spec coverage:** This plan covers backup and restore, dependency installation before start, project-level command visibility, manual browser launch, browser launch stability, and installed-browser filtering. No requirement from the current spec is intentionally omitted.

2. **Placeholder scan:** The plan does not use `TODO`, `TBD`, or “implement later” placeholders. Each task names exact files, commands, and code shapes.

3. **Type consistency:** Shared types used across tasks are consistent:
- `Project`
- `InstallStrategy`
- `TechneBackupPayload`
- `TechneBackupDocument`
- `BrowserLaunchRequest`
- `ProjectStartupCoordinator`

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-20-techne-next-iteration.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
