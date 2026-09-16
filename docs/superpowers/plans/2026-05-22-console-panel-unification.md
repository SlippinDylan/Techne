# Console Panel Unification Implementation Plan

> **Historical plan:** This document retains macOS 15 references as implementation history. The current product baseline is macOS 26.0 or later.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the visual chrome and interaction behavior of all in-app command/output panels across dev services, mini-apps, Android deployment, and the log window without collapsing different data models into one component.

**Architecture:** Introduce a shared console-surface style layer that owns the shell, padding, separators, inner viewport background, and role-based metrics for output panels. Keep `TerminalPanel` focused on streaming text behavior, and align `LogView` to the same visual system through a shared container instead of forcing structured logs into the terminal component.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, `xcodebuild`

---

## File Structure

**Create**
- `Techne/Views/Shared/Components/ConsolePanelStyle.swift`
  Pure role-based metrics and palette definitions for console-like surfaces.
- `Techne/Views/Shared/Components/ConsolePanelContainer.swift`
  Shared SwiftUI shell for terminal/log panels with header, separator, and inner viewport support.
- `TechneTests/Views/ConsolePanelStyleTests.swift`
  Unit tests for role-specific metrics so the visual system stays deterministic.

**Modify**
- `Techne/Views/Shared/Components/TerminalPanel.swift`
  Move container chrome out of ad hoc modifiers and onto the shared console container.
- `Techne/Views/ProjectCard.swift`
  Keep project command output on `TerminalPanel`, but use the unified embedded-console role consistently.
- `Techne/Views/ADBDeployView.swift`
  Keep Android deployment output on `TerminalPanel`, but align toolbar/content spacing with the shared console shell.
- `Techne/Views/Log/LogView.swift`
  Apply the same console shell to the structured log list while preserving filtering, selection, and copy actions.

## Scope Guardrails

- Do **not** convert `LogView` to `TerminalPanel`. Logs are structured and selectable row data, not stream text.
- Do **not** broaden this work to command-detail popovers or command-config form fields. Those are monospaced content fields, not runtime output panels.
- Do **not** reintroduce per-screen one-off border/background tweaks after the shared console shell exists.
- Do **not** touch unrelated output-producing services. This is a view-layer unification pass, not a process/output pipeline rewrite.

## Visual Intent

- Embedded runtime consoles inside cards should feel like one deliberate inset surface, not a random extra `ScrollView` with a border.
- Toolbars such as “复制日志 / 清除日志” should sit inside the same shell as the output and be separated from the viewport by a subtle divider.
- The log window should look like it belongs to the same family as the runtime consoles while keeping its own list affordances.
- Rounded corners, padding rhythm, separator placement, and inner viewport background should come from one source of truth.

### Task 1: Create The Shared Console Surface Style

**Files:**
- Create: `Techne/Views/Shared/Components/ConsolePanelStyle.swift`
- Create: `TechneTests/Views/ConsolePanelStyleTests.swift`

- [ ] **Step 1: Write the failing tests for console panel metrics**

Create `TechneTests/Views/ConsolePanelStyleTests.swift` with:

```swift
import Testing
@testable import Techne

struct ConsolePanelStyleTests {
    @Test
    func embeddedTerminalUsesTighterSpacingAndFixedViewportHeight() {
        let metrics = ConsolePanelStyle.metrics(for: .embeddedTerminal)

        #expect(metrics.outerCornerRadius == AppConfig.UI.mediumCornerRadius)
        #expect(metrics.contentPadding == AppConfig.UI.largePadding)
        #expect(metrics.viewportCornerRadius == AppConfig.UI.mediumCornerRadius)
        #expect(metrics.defaultViewportHeight == 200)
        #expect(metrics.showsHeaderDivider == true)
    }

    @Test
    func logWindowUsesRoomierMetricsThanEmbeddedTerminal() {
        let embedded = ConsolePanelStyle.metrics(for: .embeddedTerminal)
        let logWindow = ConsolePanelStyle.metrics(for: .logWindow)

        #expect(logWindow.outerCornerRadius >= embedded.outerCornerRadius)
        #expect(logWindow.contentPadding >= embedded.contentPadding)
        #expect(logWindow.defaultViewportHeight == nil)
        #expect(logWindow.showsHeaderDivider == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ConsolePanelStyleTests
```

Expected: FAIL because `ConsolePanelStyle` does not exist yet.

- [ ] **Step 3: Implement the style model**

Create `Techne/Views/Shared/Components/ConsolePanelStyle.swift`:

```swift
import Foundation

enum ConsolePanelRole {
    case embeddedTerminal
    case logWindow
}

struct ConsolePanelMetrics: Equatable {
    let outerCornerRadius: CGFloat
    let viewportCornerRadius: CGFloat
    let contentPadding: CGFloat
    let viewportPadding: CGFloat
    let headerSpacing: CGFloat
    let defaultViewportHeight: CGFloat?
    let showsHeaderDivider: Bool
}

enum ConsolePanelStyle {
    static func metrics(for role: ConsolePanelRole) -> ConsolePanelMetrics {
        switch role {
        case .embeddedTerminal:
            return ConsolePanelMetrics(
                outerCornerRadius: AppConfig.UI.mediumCornerRadius,
                viewportCornerRadius: AppConfig.UI.mediumCornerRadius,
                contentPadding: AppConfig.UI.largePadding,
                viewportPadding: AppConfig.UI.mediumPadding,
                headerSpacing: AppConfig.UI.mediumSpacing,
                defaultViewportHeight: 200,
                showsHeaderDivider: true
            )

        case .logWindow:
            return ConsolePanelMetrics(
                outerCornerRadius: AppConfig.UI.largeCornerRadius,
                viewportCornerRadius: AppConfig.UI.mediumCornerRadius,
                contentPadding: AppConfig.UI.largePadding,
                viewportPadding: AppConfig.UI.mediumPadding,
                headerSpacing: AppConfig.UI.largeSpacing,
                defaultViewportHeight: nil,
                showsHeaderDivider: false
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests again**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ConsolePanelStyleTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Techne/Views/Shared/Components/ConsolePanelStyle.swift TechneTests/Views/ConsolePanelStyleTests.swift
git commit -m "feat: add shared console panel style"
```

### Task 2: Build A Reusable Console Panel Container

**Files:**
- Create: `Techne/Views/Shared/Components/ConsolePanelContainer.swift`
- Modify: `Techne/Views/Shared/Components/TerminalPanel.swift`
- Test: `TechneTests/Views/ConsolePanelStyleTests.swift`

- [ ] **Step 1: Extend tests with a regression for explicit role intent**

Append to `TechneTests/Views/ConsolePanelStyleTests.swift`:

```swift
@Test
func embeddedTerminalRoleRetainsHeaderDividerForToolbarPanels() {
    let metrics = ConsolePanelStyle.metrics(for: .embeddedTerminal)

    #expect(metrics.showsHeaderDivider)
    #expect(metrics.defaultViewportHeight == 200)
}
```

- [ ] **Step 2: Run the tests before introducing the new container**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ConsolePanelStyleTests
```

Expected: PASS.

- [ ] **Step 3: Implement the shared container and refactor `TerminalPanel` onto it**

Create `Techne/Views/Shared/Components/ConsolePanelContainer.swift`:

```swift
import SwiftUI

struct ConsolePanelContainer<Header: View, Content: View>: View {
    let role: ConsolePanelRole
    let showsHeader: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    private var metrics: ConsolePanelMetrics {
        ConsolePanelStyle.metrics(for: role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header()
                    .padding(.horizontal, metrics.contentPadding)
                    .padding(.top, metrics.contentPadding)
                    .padding(.bottom, metrics.headerSpacing)

                if metrics.showsHeaderDivider {
                    Divider()
                        .padding(.horizontal, metrics.contentPadding)
                }
            }

            content()
                .padding(metrics.contentPadding)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.outerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.outerCornerRadius)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

extension ConsolePanelContainer where Header == EmptyView {
    init(
        role: ConsolePanelRole,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.role = role
        self.showsHeader = false
        self.header = { EmptyView() }
        self.content = content
    }
}
```

Refactor `Techne/Views/Shared/Components/TerminalPanel.swift` so the streaming text stays local but the shell moves to the container:

```swift
private var terminalBody: some View {
    let metrics = ConsolePanelStyle.metrics(for: .embeddedTerminal)

    return ConsolePanelContainer(
        role: .embeddedTerminal,
        showsHeader: showsToolbar,
        header: toolbarContent
    ) {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayedText)
                        .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                        .foregroundStyle(output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(metrics.viewportPadding)

                    Color.clear
                        .frame(height: 1)
                        .id("terminalBottom")
                }
            }
            .appScrollChrome(.utilityPanel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modify { view in
                if let height {
                    view.frame(height: height)
                } else if let defaultViewportHeight = metrics.defaultViewportHeight {
                    view.frame(height: defaultViewportHeight)
                } else {
                    view
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: metrics.viewportCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.viewportCornerRadius)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onChange(of: output) { _, _ in
                proxy.scrollTo("terminalBottom", anchor: .bottom)
            }
        }
    }
}
```

- [ ] **Step 4: Run focused tests and a build**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ConsolePanelStyleTests
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Expected: tests PASS, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Techne/Views/Shared/Components/ConsolePanelContainer.swift Techne/Views/Shared/Components/TerminalPanel.swift TechneTests/Views/ConsolePanelStyleTests.swift
git commit -m "feat: refactor terminal panel onto shared console shell"
```

### Task 3: Roll The Shared Console Shell Across Runtime Output Panels

**Files:**
- Modify: `Techne/Views/ProjectCard.swift`
- Modify: `Techne/Views/ADBDeployView.swift`
- Test: `TechneTests/Views/ProjectTerminalVisibilityTests.swift`

- [ ] **Step 1: Add a regression test that keeps runtime output visible after the panel refactor**

Append to `TechneTests/Views/ProjectTerminalVisibilityTests.swift`:

```swift
@Test
func keepsConsoleVisibleForRunningProjectEvenWithoutBufferedOutput() {
    var project = makeProject(type: .devServer)
    project.isRunning = true
    project.terminalOutput = ""

    #expect(ProjectTerminalVisibility.showsConsole(for: project))
    #expect(ProjectTerminalVisibility.showsToggle(for: project))
}
```

- [ ] **Step 2: Run the visibility tests first**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ProjectTerminalVisibilityTests
```

Expected: PASS.

- [ ] **Step 3: Align the runtime consumers to the shared shell**

Keep `ProjectCard` on the standard embedded terminal with no custom ad hoc shell:

```swift
private var terminalOutputView: some View {
    TerminalPanel(
        output: project.terminalOutput,
        emptyText: "等待任务启动...",
        height: ConsolePanelStyle.metrics(for: .embeddedTerminal).defaultViewportHeight
    )
    .padding(AppConfig.UI.largePadding)
}
```

Keep `ADBDeployView` using `TerminalPanel`, but let the toolbar live inside the shared console shell and avoid introducing a second local border/background:

```swift
private var consoleSection: some View {
    TerminalPanel(output: viewModel.terminalOutput, emptyText: "等待任务启动...") {
        if !viewModel.terminalOutput.isEmpty {
            HStack {
                Spacer()

                Button("复制日志") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.terminalOutput, forType: .string)
                }
                .adaptiveGlassButtonStyle()
                .controlSize(.small)

                Button("清除日志") { viewModel.clearTerminal() }
                    .adaptiveGlassButtonStyle()
                    .controlSize(.small)
            }
        }
    }
}
```

Manual review target while implementing:
- `ProjectCard` console should feel inset but not visually detached from the card.
- `ADBDeployView` console should feel like the same family as the project-card console, not a separate design language.

- [ ] **Step 4: Run the visibility tests and a build**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ProjectTerminalVisibilityTests
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Expected: tests PASS, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Techne/Views/ProjectCard.swift Techne/Views/ADBDeployView.swift TechneTests/Views/ProjectTerminalVisibilityTests.swift
git commit -m "feat: align runtime output panels"
```

### Task 4: Align The Log Window To The Same Console Family

**Files:**
- Modify: `Techne/Views/Log/LogView.swift`
- Test: `TechneTests/Views/ConsolePanelStyleTests.swift`

- [ ] **Step 1: Add a regression test for the log-window role**

Append to `TechneTests/Views/ConsolePanelStyleTests.swift`:

```swift
@Test
func logWindowRoleDoesNotImposeFixedViewportHeight() {
    let metrics = ConsolePanelStyle.metrics(for: .logWindow)

    #expect(metrics.defaultViewportHeight == nil)
    #expect(metrics.showsHeaderDivider == false)
}
```

- [ ] **Step 2: Run the style tests**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ConsolePanelStyleTests
```

Expected: PASS.

- [ ] **Step 3: Wrap the structured log list in the shared shell without replacing the `List`**

Refactor `Techne/Views/Log/LogView.swift`:

```swift
private var logListCard: some View {
    ConsolePanelContainer(role: .logWindow) {
        Group {
            if filteredLogs.isEmpty {
                VStack(spacing: AppConfig.UI.mediumSpacing) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("No logs yet")
                        .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium))

                    Text("Logs will appear here")
                        .font(.system(size: AppConfig.UI.smallFontSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppConfig.UI.extraLargePadding)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: ConsolePanelStyle.metrics(for: .logWindow).viewportCornerRadius))
            } else {
                List(filteredLogs, selection: $selection) { log in
                    Text(formatLogLine(log))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(logColor(for: log.level))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: ConsolePanelStyle.metrics(for: .logWindow).viewportCornerRadius))
                .appScrollChrome(.mainContent)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

This keeps the log window’s data behavior intact while making the container feel like the same output system as runtime consoles.

- [ ] **Step 4: Run style tests and a build**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' -only-testing:TechneTests/Views/ConsolePanelStyleTests
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Expected: tests PASS, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Techne/Views/Log/LogView.swift TechneTests/Views/ConsolePanelStyleTests.swift
git commit -m "feat: align log window console chrome"
```

### Task 5: Final Visual And Behavior Verification

**Files:**
- Modify: none
- Test: existing focused tests plus manual QA checklist

- [ ] **Step 1: Run the focused automated tests**

Run:

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS' \
  -only-testing:TechneTests/Views/ConsolePanelStyleTests \
  -only-testing:TechneTests/Views/ProjectTerminalVisibilityTests
```

Expected: PASS.

- [ ] **Step 2: Run a final build**

Run:

```bash
xcodebuild build -quiet -project Techne.xcodeproj -scheme Techne -configuration Debug -derivedDataPath ./build-local-debug-analysis CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Perform manual QA on every output surface**

Manual verification checklist:
- 开发服务项目卡片里的终端输出区：
  - shell、边框、内边距、滚动区层级统一
  - 输出增长时自动滚到底
  - 滚动条仍遵循上一轮的系统策略
- 微信小程序项目卡片里的终端输出区：
  - 与开发服务卡片视觉一致
  - 没有额外双重边框
- 安卓应用部署输出区：
  - “复制日志 / 清除日志”工具栏与输出区在同一外壳里
  - 大量输出时不裁切、不抖动
- 日志窗口：
  - 仍支持筛选、多选、复制
  - 容器视觉与运行时终端同家族
  - `List` 背景不再与外层 shell 打架
- macOS 15 与当前 macOS 26：
  - 所有输出区滚动条与 shell 外观都保持原生感

- [ ] **Step 4: Commit any final polish if needed**

```bash
git add -A -- .
git commit -m "test: verify unified console panels"
```

## Self-Review

- Spec coverage:
  - 开发服务、微信小程序、安卓应用的命令框统一由 Task 2 和 Task 3 覆盖。
  - 日志窗口的视觉对齐由 Task 4 覆盖，并明确保留结构化 `List`。
  - 不扩大到命令详情弹窗和命令配置字段的范围由 Scope Guardrails 明确约束。
- Placeholder scan:
  - No `TODO`, `TBD`, or “similar to above” placeholders remain.
- Type consistency:
  - `ConsolePanelRole`, `ConsolePanelMetrics`, `ConsolePanelStyle`, and `ConsolePanelContainer` are used consistently across all tasks.

Plan complete and saved to `docs/superpowers/plans/2026-05-22-console-panel-unification.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
