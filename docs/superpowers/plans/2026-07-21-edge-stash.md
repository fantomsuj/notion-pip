# Edge Stash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native-feeling edge tab that temporarily stashes the live Perch and restores it without changing the page, WebView session, or saved panel frame.

**Architecture:** A pure `PanelStashPolicy` computes edge-tab placement from panel and screen geometry. `PiPPanelCoordinator` coordinates the existing PiP panel with a narrow AppKit handle controller, while SwiftUI receives only stash and restore callbacks.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, macOS 14+

## Global Constraints

- Preserve the current `NotionWebSession`, `currentPage`, main-panel frame, and frame autosave identity while stashed.
- Use the screen with the greatest panel intersection and the nearest horizontal edge.
- Keep the restore handle fully within the chosen screen's visible frame and available across Spaces.
- If no visible screen exists, an explicit toolbar stash leaves the panel visible; the global shortcut falls back to hiding it.
- Preserve the user's existing uncommitted `PageURLInputPresenterTests.swift` edit without including it in the feature commit.

---

### Task 1: Stash placement policy

**Files:**
- Create: `Sources/Perch/Platform/PanelStashPolicy.swift`
- Modify: `Sources/Perch/Platform/PanelFramePolicy.swift`
- Test: `Tests/PerchTests/PanelStashPolicyTests.swift`

**Interfaces:**
- Consumes: `PanelFramePolicy.targetVisibleFrame(for:from:)`
- Produces: `PanelStashSide`, `PanelStashPlacement`, and `PanelStashPolicy.placement(for:visibleFrames:) -> PanelStashPlacement?`

- [x] **Step 1: Write focused tests for left/right choice, screen selection, vertical clamping, and empty screens.**
- [x] **Step 2: Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelStashPolicyTests` and verify the tests fail because the policy does not exist.**
- [x] **Step 3: Implement the minimal pure geometry policy and expose the existing target-screen helper at module scope.**
- [x] **Step 4: Re-run the focused tests and verify they pass.**

### Task 2: Coordinator stash lifecycle

**Files:**
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Modify: `Tests/PerchTests/PinCoordinatorTests.swift`

**Interfaces:**
- Consumes: `PanelStashPlacement` and the existing `PiPPanelWindow`
- Produces: `PiPStashHandle`, `PiPPanelCoordinator.stash(visibleFrames:) -> Bool`, `PiPPanelCoordinator.restoreFromStash()`, and `stashOrRestoreCurrentPage() -> Bool`

- [x] **Step 1: Add fake-handle tests proving stash orders out the main panel without reloading or changing its frame, restore presents it, show/hide cleans up the handle, screen changes reposition it, and the global-shortcut path alternates stash/restore.**
- [x] **Step 2: Run the focused coordinator tests and verify they fail for the missing lifecycle.**
- [x] **Step 3: Implement the smallest coordinator state transitions needed to pass, keeping the handle optional in test-only construction.**
- [x] **Step 4: Re-run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PinCoordinatorTests` and verify it passes.**

### Task 3: Edge-handle UI and toolbar action

**Files:**
- Create: `Sources/Perch/Platform/PiPStashHandleController.swift`
- Create: `Sources/Perch/Views/PiPStashHandleView.swift`
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Modify: `Sources/Perch/Views/PiPChromeView.swift`
- Modify: `Tests/PerchTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: `PiPStashHandle`, `PanelStashPlacement`, and coordinator stash/restore operations
- Produces: a borderless nonactivating handle panel and `PiPChromeView.onStash`

- [x] **Step 1: Add a view-surface regression assertion that the PiP chrome exposes the stash action and accessibility copy.**
- [x] **Step 2: Run the focused view test and verify it fails for the absent control.**
- [x] **Step 3: Build the SwiftUI edge tab, its AppKit host, and wire the toolbar callback through the production coordinator initializer.**
- [x] **Step 4: Re-run the focused tests and the Swift compiler checks.**

### Task 4: Verification and commit

**Files:**
- Modify: `README.md`
- Review: all feature files above

**Interfaces:**
- Consumes: completed edge-stash feature
- Produces: user-facing documentation and a verified commit

- [x] **Step 1: Document the stash and restore interaction in `README.md`.**
- [x] **Step 2: Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`, `npm test`, `npm run typecheck`, and `./script/build_and_run.sh --verify`.**
- [x] **Step 3: Review `git diff origin/master...` plus the working-tree diff, confirm the unrelated user edit is excluded, and inspect for placeholders or debug output.**
- [x] **Step 4: Commit only the edge-stash implementation, tests, research design, plan, and README update.**
