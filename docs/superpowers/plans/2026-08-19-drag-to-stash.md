# Drag-to-Stash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stash Perch when the user releases a panel drag with at least 40% of its width beyond a true horizontal display edge, then release it as version 0.1.1.

**Architecture:** Add a pure geometry decision to `PanelStashPolicy` and consume it from `PiPPanelCoordinator`'s existing deferred drag-completion path. Reuse the current stash handle, animation, restoration, and lifecycle plumbing.

**Tech Stack:** Swift 6.2, AppKit, CoreGraphics, XCTest, Swift Package Manager, shell release scripts

**Spec:** `docs/superpowers/plans/2026-08-19-drag-to-stash-design.md`

## Global Constraints

- Preserve macOS 14 and Swift 6.2 support.
- Stash only on release, never while the drag is active.
- Only true outer left and right display edges qualify.
- The threshold is exactly 40% of panel width.
- Reuse the existing stash handle and transition.
- Do not create global event monitors or accessibility requirements.

---

### Task 1: Drag stash geometry

**Files:**
- Modify: `Sources/Perch/Platform/PanelStashPolicy.swift`
- Test: `Tests/PerchTests/PanelStashPolicyTests.swift`

**Interfaces:**
- Produces: `PanelDragStashDecision` and `PanelStashPolicy.dragDecision(for:topology:hiddenFraction:)`

- [ ] Add failing tests for left/right thresholds, cancellation below threshold, top/bottom exclusion, adjacent displays, restore-frame clamping, and handle placement.
- [ ] Run `swift test --filter PanelStashPolicyTests` and confirm the new API is missing.
- [ ] Implement the minimal pure geometry policy and outer-edge detection.
- [ ] Run `swift test --filter PanelStashPolicyTests` and confirm it passes.

### Task 2: Commit stash on drag completion

**Files:**
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Test: `Tests/PerchTests/PinCoordinatorTests.swift`

**Interfaces:**
- Consumes: `PanelStashPolicy.dragDecision(for:topology:hiddenFraction:)`
- Produces: `PiPPanelCoordinator.finishPanelMove()` for the deferred release path.

- [ ] Add failing coordinator tests proving the panel remains visible while pressed, stashes after release, persists the on-screen restore frame, skips corner snapping, and waits for trackpad movement to end.
- [ ] Run the focused coordinator tests and confirm failure.
- [ ] Replace the corner-only deferred completion with `finishPanelMove()`, committing the existing stash transition when a drag decision exists.
- [ ] Run the focused coordinator tests and confirm they pass.

### Task 3: Documentation and regression verification

**Files:**
- Modify: `README.md`
- Modify: `docs/DISTRIBUTION.md`

- [ ] Document drag-to-stash behavior and recovery through the edge handle.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- [ ] Run all scripts under `Tests/ScriptTests`.
- [ ] Run `git diff --check` and review the focused diff.

### Task 4: Version and release candidate

**Files:**
- Modify: `Support/Version.env`
- Modify: release/updater files only if the current branch lacks the approved Sparkle implementation.

- [ ] Confirm the current version and set short version `0.1.1` with a build number greater than the 0.1.0 baseline.
- [ ] Build and verify the staged app with `./script/build_and_run.sh --verify` after confirming no user-owned Perch process is running.
- [ ] Validate the DMG/appcast and perform the local 0.1.0 to 0.1.1 upgrade.
- [ ] Review release credentials and artifact URLs without printing secrets.
- [ ] Create the release tag only after all prior checks pass.
