# Console Stability And Project-Root Stop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the shared log viewport stop rendering blank frames during live output updates, and make project stop operations terminate all matching processes under the managed project root.

**Architecture:** Keep the console fix isolated to the shared AppKit-backed viewport so every module benefits without touching business views. For stopping, introduce a focused project-root process matcher and a stop-plan resolver inside the process layer, then route project stop flows through that resolver instead of trusting a single remembered PID.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, `xcodebuild`

---

### Task 1: Stabilize the shared console viewport

**Files:**
- Modify: `Techne/Views/Shared/Components/ConsoleTextViewport.swift`
- Test: `TechneTests/Views/ConsolePanelStyleTests.swift`

- [ ] Add failing tests that prove the shared terminal viewport keeps its clip view within the legal bottom range after output updates.
- [ ] Verify the tests fail against the current auto-scroll implementation.
- [ ] Implement a small viewport state helper inside the shared console component so layout, bottom-offset calculation, and auto-follow decisions are explicit.
- [ ] Re-run the targeted console tests after cleaning build cache.

### Task 2: Stop processes by managed project root instead of one remembered PID

**Files:**
- Create: `Techne/Services/Shared/ProjectRootProcessMatcher.swift`
- Modify: `Techne/Services/Shared/ProcessService.swift`
- Modify: `Techne/Services/Shared/ProcessManager.swift`
- Modify: `Techne/Services/ProjectService.swift`
- Test: `TechneTests/Startup/ProjectServiceStartupRecoveryTests.swift`
- Test: `TechneTests/Services/ProcessServiceProjectScopeTests.swift`

- [ ] Add failing pure tests for project-root process matching and stop-plan resolution, including nested paths and sibling rejection.
- [ ] Add a failing project-service test proving stop uses project-root matches even when the stored running PID does not represent the final listener.
- [ ] Introduce a small process snapshot model plus a resolver that finds matching PIDs/PGIDs by project-root ownership, with dependency injection for tests.
- [ ] Route both dev-server stop paths through the resolver and keep state reconciliation scoped to the project root.
- [ ] Re-run the targeted process tests plus the impacted startup recovery suite after cleaning build cache.

### Task 3: Final verification and review

**Files:**
- Modify: none expected unless review finds issues

- [ ] Run the impacted regression suite after cleaning build cache.
- [ ] Review the final diff for bugs, regressions, and missing edge cases before handing off.
