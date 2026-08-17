# PiP Trackpad Move Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add precise two-finger movement for the visible Perch PiP across its hidden and visible top-controls region.

**Architecture:** A value-driven `TopEdgeTrackpadMoveController` classifies and latches AppKit scroll gestures without depending on hardware-created events. `KeyCapablePiPPanel` adapts `NSEvent`, constrains accepted movement to the gesture's starting display, and relies on existing window-move notifications for persistence and corner snapping.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, XCTest, macOS 14+

## Global Constraints

- Preserve Swift 6.2, macOS 14, the current public API, signing, and entitlement contracts.
- Preserve the intentional persistent, all-Spaces `NSPanel` behavior.
- Do not intercept scrolling in the Notion content area.
- Stop panel movement at physical gesture end and ignore momentum movement.
- Keep the panel reachable inside the starting display's visible frame.
- Keep tests independent because Swift tests may run in parallel.

---

### Task 1: Deterministic top-edge gesture policy

**Files:**
- Create: `Sources/Perch/Platform/TopEdgeTrackpadMoveController.swift`
- Create: `Tests/PerchTests/TopEdgeTrackpadMoveControllerTests.swift`

**Interfaces:**
- Consumes: `CoreGraphics.CGPoint`, `CGSize`, and `NSEvent.Phase`-independent value phases.
- Produces: `TopEdgeTrackpadMoveController.handle(_:) -> TopEdgeTrackpadMoveDecision`, `TopEdgeTrackpadMoveInput`, and `TopEdgeTrackpadMoveController.activeHeight`.

- [ ] **Step 1: Write failing tests for gesture admission**

  Add tests whose literal inputs prove that precise, non-expanded gestures begin at y coordinates inside the top 36 points, including the top 16-point reveal strip, while the exact lower boundary, imprecise scrolling, expanded panels, and missing display bounds return `.forward`.

- [ ] **Step 2: Run the focused tests and verify RED**

  Run:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TopEdgeTrackpadMoveControllerTests
  ```

  Expected: compilation fails because the new controller and value types do not exist.

- [ ] **Step 3: Implement admission and movement state**

  Create value phases for `began`, `changed`, `ended`, `cancelled`, and `none`; an input containing phase, momentum phase, precise-delta state, pointer/content geometry, expanded state, display visible frame, and translation; and decisions `.forward`, `.consume`, and `.move(CGSize, visibleFrame: CGRect)`. Accept only precise `.began` input inside the top band with a resolved display, latch changed events, consume ended/cancelled events, and clear active state.

- [ ] **Step 4: Run the focused tests and verify GREEN**

  Run the focused command from Step 2 and require 0 failures.

- [ ] **Step 5: Write failing tests for momentum and lifecycle edge cases**

  Add literal tests proving that zero-delta active events return `.consume`, every momentum phase after an accepted gesture is consumed without movement, momentum completion resets suppression, and a later ordinary scroll returns `.forward`.

- [ ] **Step 6: Run the focused tests and verify RED**

  Run the focused command and confirm at least one new assertion fails because momentum suppression is not implemented.

- [ ] **Step 7: Implement minimal momentum suppression**

  Retain suppression after physical gesture completion, consume momentum without returning a translation, and clear suppression on momentum ended/cancelled.

- [ ] **Step 8: Run the focused tests and verify GREEN**

  Run the focused command and require 0 failures.

- [ ] **Step 9: Commit the deterministic policy**

  ```sh
  git add Sources/Perch/Platform/TopEdgeTrackpadMoveController.swift Tests/PerchTests/TopEdgeTrackpadMoveControllerTests.swift
  git commit -m "Add top-edge trackpad move policy"
  ```

### Task 2: Integrate the policy with the PiP panel

**Files:**
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Modify: `Sources/Perch/Views/PiPChromeView.swift`
- Modify: `Tests/PerchTests/PiPPanelGeometryTests.swift`
- Modify: `Tests/PerchTests/PiPChromeViewTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `TopEdgeTrackpadMoveController.handle(_:)`, `TopEdgeTrackpadMoveDecision`, and `TopEdgeTrackpadMoveController.activeHeight` from Task 1.
- Produces: panel-level `NSEvent` adaptation and constrained two-axis movement while preserving existing `NSWindow.didMoveNotification` integration.

- [ ] **Step 1: Write failing panel and chrome integration tests**

  Add a panel test entry point that feeds controller inputs through the real `KeyCapablePiPPanel`, then assert a literal frame origin after a two-axis move and a literal clamped origin after movement beyond the starting visible frame. Add a chrome test asserting its toolbar height is sourced from the shared gesture height through equal behavior, not duplicated gesture logic.

- [ ] **Step 2: Run the integration tests and verify RED**

  Run:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PiPPanelGeometryTests|PiPChromeViewTests'
  ```

  Expected: compilation fails because the panel integration entry point does not exist.

- [ ] **Step 3: Implement panel event adaptation**

  Give `KeyCapablePiPPanel` one controller instance. Override `sendEvent(_:)`; forward all non-scroll events, convert every AppKit scroll phase into the value input, resolve the gesture-starting display from `NSScreen.screens`, and apply `.move` decisions with `PanelFramePolicy.clamped(_:visibleFrames:)`. Consume accepted/stationary/end/momentum events and forward `.forward` decisions to AppKit. Expose active gesture state through `PiPPanelWindow` so corner snapping waits for physical completion, and reset interrupted state when the panel orders out. Keep the test entry point internal and route it through the same decision application method as `sendEvent(_:)`.

- [ ] **Step 4: Share the active height with SwiftUI**

  Set `PiPChromeView.topControlsHeight` from `TopEdgeTrackpadMoveController.activeHeight`, leaving `topControlsRevealHeight` at 16 points.

- [ ] **Step 5: Run focused integration and policy tests**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'TopEdgeTrackpadMoveControllerTests|PiPPanelGeometryTests|PiPChromeViewTests'
  ```

  Require 0 failures.

- [ ] **Step 6: Document the interaction**

  Update the README feature list to state that two-finger movement works from the top edge while ordinary Notion scrolling remains unchanged.

- [ ] **Step 7: Run the full suite**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

  Require 0 failures and report any pre-existing warnings separately.

- [ ] **Step 8: Commit panel integration and documentation**

  ```sh
  git add Sources/Perch/Platform/PiPPanelCoordinator.swift Sources/Perch/Views/PiPChromeView.swift Tests/PerchTests/PiPPanelGeometryTests.swift Tests/PerchTests/PiPChromeViewTests.swift README.md
  git commit -m "Move PiP with two-finger top-edge gestures"
  ```

### Task 3: Review and release readiness

**Files:**
- Verify: all files changed since `origin/master`

**Interfaces:**
- Consumes: the complete feature branch.
- Produces: a reviewed, synchronized, fully verified draft pull request ready to merge.

- [ ] **Step 1: Self-review scope and requirements**

  Inspect `git diff origin/master...HEAD`, confirm no unrelated files changed, and check every design requirement against implementation and tests.

- [ ] **Step 2: Request independent code review**

  Provide the reviewer with the design, implementation plan, base SHA, and head SHA. Resolve every Critical or Important finding with a new failing regression test before changing production code.

- [ ] **Step 3: Verify before publishing**

  Run the full Swift suite again and inspect `git status --short` and `git diff --check` before pushing.

- [ ] **Step 4: Synchronize with the target branch**

  Fetch `origin/master`, merge it into `agent/pip-trackpad-move` without force-pushing, resolve conflicts in favor of the approved behavior and upstream-compatible APIs, then rerun the full suite.

- [ ] **Step 5: Publish a draft pull request**

  Push `agent/pip-trackpad-move`, open a draft PR against `master`, and include behavior, architecture, tests, and manual-verification notes in the body.

- [ ] **Step 6: Drive PR CI to green**

  Watch all PR checks. For each failure, inspect GitHub Actions logs, add a failing local regression when the failure represents product behavior, apply the narrow fix, rerun relevant and full tests, push, and repeat until every required check passes.

- [ ] **Step 7: Merge and verify post-merge CI**

  Mark the PR ready if repository policy requires it, merge through GitHub using the repository's allowed merge method, identify the resulting `master` commit, and watch every workflow/check associated with that commit to a successful terminal state.
