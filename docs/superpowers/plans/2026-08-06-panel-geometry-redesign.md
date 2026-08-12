# Panel Geometry Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the last completed PiP resize and move authoritative so stash/restore preserves exact geometry, with Horizontal and Vertical built-ins.

**Architecture:** Add one versioned `PanelGeometry` snapshot and pure `PanelGeometryPolicy`, persist it through a dedicated store, and make `PiPPanelCoordinator` commit or resolve that snapshot at every geometry boundary. Stash state owns visibility and handle placement only. Existing size preferences retain custom presets but migrate legacy built-in identifiers to Horizontal or Vertical.

**Tech Stack:** Swift 6.2, AppKit `NSPanel`, SwiftUI, Core Graphics, `UserDefaults`, XCTest, Swift Package Manager

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Preserve the retained, floating, all-Spaces PiP panel behavior.
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` for source validation.
- Use `./script/build_and_run.sh --verify` for staged-app launch verification.
- Do not require Node.js, secrets, a Notion token, or signing certificates.
- Write every behavior test first and observe the expected failure before production changes.

---

## File Map

- Create `Sources/Perch/Domain/PanelGeometry.swift`: versioned geometry snapshot and validation.
- Create `Sources/Perch/Persistence/PanelGeometryStore.swift`: dedicated `UserDefaults` persistence boundary.
- Create `Sources/Perch/Platform/PanelGeometryPolicy.swift`: capture and resolve geometry without window ownership.
- Modify `Sources/Perch/Platform/PanelFramePolicy.swift`: make the existing anchor value Codable and Sendable for the snapshot.
- Modify `Sources/Perch/Platform/PiPPanelCoordinator.swift`: replace parallel geometry fields with the unified snapshot and guard stash animation ordering.
- Modify `Sources/Perch/Domain/PanelSizePreferences.swift`: Horizontal/Vertical built-ins and legacy decoding.
- Modify `Sources/Perch/App/PanelSizeController.swift`: Vertical reset and built-in/custom application through the same commit path.
- Modify `Sources/Perch/Views/PanelSizeMenu.swift`: expose Horizontal, Vertical, custom sizes, Reset, and management.
- Modify `Sources/Perch/Views/PanelSizeSettingsView.swift`: remove competing default selection and show the two built-ins.
- Create `Tests/PerchTests/PanelGeometryTests.swift`: snapshot validation and policy behavior.
- Create `Tests/PerchTests/PanelGeometryStoreTests.swift`: persistence and corrupt-data behavior.
- Modify `Tests/PerchTests/PanelSizePreferencesTests.swift`: built-ins and migration.
- Modify `Tests/PerchTests/PanelSizeControllerTests.swift`: reset and application behavior.
- Modify `Tests/PerchTests/PinCoordinatorTests.swift`: exact stash/restore geometry, display changes, and transition ordering.
- Modify `Tests/PerchTests/PiPPanelGeometryTests.swift`: real-AppKit horizontal and vertical restoration.
- Modify `docs/MANUAL_TEST_MATRIX.md`: Horizontal/Vertical and exact restore checks.

---

### Task 1: Unified Geometry Model, Policy, And Store

**Interfaces:**

- Produces `PanelGeometry.init(desiredContentSize:frame:visibleFrame:anchor:) throws`.
- Produces `PanelGeometryPolicy.capture(frame:visibleFrames:desiredContentSize:contentRectForFrameRect:) -> PanelGeometry?`.
- Produces `PanelGeometryPolicy.resolvedFrame(for:visibleFrames:minimumContentSize:frameForContentRect:) -> CGRect`.
- Produces `PanelGeometryPersisting.load() -> PanelGeometry?` and `save(_:) throws`.

- [ ] **Step 1: Write failing policy tests**

Add literal tests proving that capture records a 760 × 520 horizontal frame and its nearest edges, same-display resolution returns that exact frame, display replacement uses the saved anchor, and a 500 × 400 display clamps without replacing the 760 × 520 desired size.

- [ ] **Step 2: Run policy tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelGeometryTests
```

Expected: compilation fails because `PanelGeometry` and `PanelGeometryPolicy` do not exist.

- [ ] **Step 3: Implement the model and pure policy**

Use this production interface:

```swift
struct PanelGeometry: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let desiredContentSize: PanelContentSize
    let frame: CGRect
    let visibleFrame: CGRect
    let anchor: PanelFrameAnchor
}

enum PanelGeometryPolicy {
    static func capture(
        frame: CGRect,
        visibleFrames: [CGRect],
        desiredContentSize: CGSize? = nil,
        contentRectForFrameRect: (CGRect) -> CGRect
    ) -> PanelGeometry?

    static func resolvedFrame(
        for geometry: PanelGeometry,
        visibleFrames: [CGRect],
        minimumContentSize: CGSize,
        frameForContentRect: (CGRect) -> CGRect
    ) -> CGRect
}
```

Make `PanelFrameAnchor` and its edge enums conform to `Codable` and `Sendable`. Validate the version and all frame/content dimensions during decoding.

- [ ] **Step 4: Run policy tests and verify GREEN**

Run the Task 1 policy command and require zero failures.

- [ ] **Step 5: Write failing persistence tests**

Cover round-trip save/load, absent data returning `nil`, and corrupt data returning `nil` so the coordinator can apply its Vertical fallback.

- [ ] **Step 6: Run store tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelGeometryStoreTests
```

Expected: compilation fails because `PanelGeometryStore` does not exist.

- [ ] **Step 7: Implement the store and verify GREEN**

Use:

```swift
protocol PanelGeometryPersisting {
    func load() -> PanelGeometry?
    func save(_ geometry: PanelGeometry) throws
}

final class PanelGeometryStore: PanelGeometryPersisting {
    static let key = "panelGeometry"
}
```

Run both Task 1 test filters and require zero failures.

- [ ] **Step 8: Commit Task 1**

Stage only the Task 1 model, policy, store, and tests. Commit `Add unified panel geometry state`.

### Task 2: Horizontal And Vertical Size Preferences

**Interfaces:**

- `BuiltInPanelSizePreset` exposes `.horizontal` and `.vertical` in that order.
- Horizontal resolves to 760 × 520 points.
- Vertical resolves to 480 × 720 points.
- Legacy `compact` and `comfortable` decode as Vertical; legacy `wide` decodes as Horizontal.
- `PanelSizeController.resetToDefault()` applies Vertical.

- [ ] **Step 1: Replace built-in expectation tests and add legacy decoding tests**

Use literal dimensions and encoded legacy payloads. Add a controller test proving Reset applies exactly 480 × 720 and does not consult a stored default identifier.

- [ ] **Step 2: Run size tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PanelSizePreferencesTests|PanelSizeControllerTests|PanelSizePreferencesStoreTests'
```

Expected: failures name missing Horizontal/Vertical cases and the old reset behavior.

- [ ] **Step 3: Implement built-in migration and controller behavior**

Give `BuiltInPanelSizePreset` a custom decoder that accepts both new and legacy raw strings. Normalize decoded preferences to the current version and map legacy default IDs without discarding custom presets. Remove the Default picker/suffix behavior from controller and settings UI. Keep custom preset add, edit, apply, and delete behavior.

- [ ] **Step 4: Run size tests and verify GREEN**

Run the Task 2 test command and require zero failures.

- [ ] **Step 5: Commit Task 2**

Stage the preference, controller, menu, settings, and related tests. Commit `Add horizontal and vertical panel sizes`.

### Task 3: Make Committed Geometry Authoritative

**Interfaces:**

- `PiPPanelCoordinator` accepts `geometryStore: any PanelGeometryPersisting` in its initializers.
- `committedGeometry` is its only long-lived geometry value.
- `commitCurrentGeometry(desiredContentSize:)` captures and persists an atomic snapshot.
- `restoreCommittedPanelFrame()` resolves the snapshot and sets the panel frame.
- `PanelSizing.onGeometryPersistenceFailure` reports a nonblocking save failure to `PanelSizeController.validationMessage`.
- `stashedPanelFrame`, `preferredWorkingContentSize`, `preservedFrameAnchor`, and `preferredVisibleFrame` are removed.

- [ ] **Step 1: Write the horizontal regression test**

In `PinCoordinatorTests`, initialize a fake panel at a literal 760 × 520 frame while injecting a conflicting legacy/preferred 480 × 720 value. Show, stash, restore, and assert the exact original 760 × 520 frame. This test catches any restore path that recalculates from stale sizing state.

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PinCoordinatorTests/testStashRestorePreservesCommittedHorizontalFrameWhenLegacySizeConflicts
```

Expected: restored frame is the stale narrow size rather than the original horizontal frame.

- [ ] **Step 3: Add failing move, preset, and display tests**

Cover exact vertical restore, applying Horizontal then stashing/restoring, manual move retaining desired content size, small-display clamping, and large-display restoration.

- [ ] **Step 4: Implement unified coordinator state**

Load unified geometry before first presentation. If absent, migrate once from the already-restored AppKit frame plus `lastExplicitWorkingContentSize`; otherwise use Vertical. Commit on completed manual resize, settled move/snap, preset application, and immediately before stash. Resolve on restore and screen changes. Do not persist screen-change clamps as new user geometry. Log store failures, keep the in-memory snapshot active, and notify the bound size controller without blocking presentation.

- [ ] **Step 5: Run coordinator tests and verify GREEN**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PinCoordinatorTests
```

Require zero failures.

- [ ] **Step 6: Commit Task 3**

Stage coordinator, wiring, and coordinator tests. Commit `Preserve committed panel geometry`.

### Task 4: Stash Animation Ordering And Real-AppKit Regression

**Interfaces:**

- `PiPPanelWindow.cancelPendingStashDismissal()` invalidates an in-flight dismissal.
- `KeyCapablePiPPanel` ignores stale animation completions.
- Restore cancels dismissal before setting the committed frame and presenting.

- [ ] **Step 1: Write a failing stale-completion test**

Use a fake panel that retains the stash completion. Restore before invoking that completion, invoke it late, and assert the panel remains visible at the committed frame.

- [ ] **Step 2: Run the transition test and verify RED**

Run the exact `PinCoordinatorTests` method. Expected: the late completion orders out or moves the restored panel.

- [ ] **Step 3: Implement generation-based cancellation**

Invalidate the panel's stash animation generation from every restore/show path. Guard completion before order-out, frame reset, alpha reset, and lifecycle callback. Ignore move notifications while stash dismissal is active.

- [ ] **Step 4: Add the real-AppKit restore tests**

Extend `PiPPanelGeometryTests` to show a real `KeyCapablePiPPanel`, set literal horizontal and vertical frames, stash, restore from the retained handle callback, drain the run loop, and compare exact frame widths and heights.

- [ ] **Step 5: Run geometry integration tests and verify GREEN**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PiPPanelGeometryTests|PinCoordinatorTests'
```

Require zero failures.

- [ ] **Step 6: Commit Task 4**

Stage transition code and integration tests. Commit `Harden panel stash restoration`.

### Task 5: Documentation And Full Verification

- [ ] **Step 1: Update the manual test matrix**

Document first-run Vertical, one-click Horizontal/Vertical, exact same-display stash restoration, rapid restore during animation, and display disconnect/reconnect behavior.

- [ ] **Step 2: Run formatting and diff checks**

Run:

```sh
git diff --check
```

Require no output and exit 0.

- [ ] **Step 3: Run the full Swift test suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Require exit 0 and zero failures.

- [ ] **Step 4: Build, launch, and verify the staged app**

First run `pgrep -x Perch`. If it is already running, terminate only the test-launched/staged process when ownership is clear; otherwise do not risk user edits. Then run:

```sh
./script/build_and_run.sh --verify
```

Require the script's `Verified .../dist/Perch.app` output and process ID. Quit the verified staged process after the check.

- [ ] **Step 5: Commit Task 5**

Stage the manual matrix and any focused verification fixes. Commit `Document panel geometry verification`.

- [ ] **Step 6: Publish and land**

Push the existing branch without renaming it, open a draft PR against `master`, monitor every GitHub Actions check, fix failures with evidence from Actions logs, mark the PR ready, merge it, and monitor the resulting `master` workflow runs to successful completion.
