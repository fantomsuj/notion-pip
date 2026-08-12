# Typing-Aware PiP Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the PiP's top actions during real Notion editing and restore them on pointer, focus, keyboard-navigation, or page-navigation activity.

**Architecture:** A document-start main-frame script emits semantic editor activity through a Notion-origin-restricted weak WebKit bridge. `NotionWebSession` publishes the resulting writing state, and `PiPChromeView` uses it to animate only the existing top actions without changing toolbar layout.

**Tech Stack:** Swift 6.2, SwiftUI, WebKit, XCTest, macOS 14+

## Global Constraints

- Accept bridge messages only from the main HTTPS frame on `notion.so` or `www.notion.so`.
- Use `beforeinput`, not private Notion DOM class names or generic key-down activity, as the edit trigger.
- Preserve the toolbar's 32-point layout and respect reduced-motion preferences.
- Do not modify unrelated files or stage changes created by other agents.

---

### Task 1: Editor Activity State and Bridge

**Files:**
- Modify: `Tests/PerchTests/NotionWebSessionTests.swift`
- Modify: `Sources/Perch/Platform/NotionWebSession.swift`

**Interfaces:**
- Produces: `NotionEditorActivity`, `NotionEditorActivityBridge.activity(...)`, `NotionWebSession.isTypingInPage`, `handleEditorActivity(_:)`, and `revealTopControls()`.

- [x] **Step 1: Write failing tests** for valid/invalid message contexts, activity state transitions, script installation, and navigation reset.
- [x] **Step 2: Verify RED** with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests`; expect missing activity bridge/session APIs.
- [x] **Step 3: Implement the minimal bridge** with a weak handler, a document-start main-frame user script, strict origin checks, and published writing state.
- [x] **Step 4: Verify GREEN** with the same focused test command; expect all `NotionWebSessionTests` to pass.

### Task 2: Typing-Aware SwiftUI Actions

**Files:**
- Modify: `Tests/PerchTests/NotionWebSessionTests.swift`
- Modify: `Sources/Perch/Views/PiPChromeView.swift`

**Interfaces:**
- Consumes: `NotionWebSession.isTypingInPage` and `revealTopControls()`.
- Produces: `PiPChromeView.showsTopControls`, animated action opacity, disabled hidden hit testing, and hover restoration.

- [x] **Step 1: Write a failing view-policy test** that starts visible, hides after typing activity, and restores after editing ends.
- [x] **Step 2: Verify RED** with the focused session test command; expect the missing `showsTopControls` API.
- [x] **Step 3: Apply the visibility policy** to the existing action group, using a 160 ms ease-out transition or no animation when Reduce Motion is enabled.
- [x] **Step 4: Verify GREEN** with the focused session test command.

### Task 3: Full Verification and Commit

**Files:**
- Verify only; update the checkboxes in this plan after commands complete.

- [ ] **Step 1: Run all Swift tests** with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; expect zero failures.
- [x] **Step 2: Run packaged-app verification** with `./script/build_and_run.sh --verify`; expect a successful build and verification exit code 0.
- [x] **Step 3: Recheck shared-worktree changes** with `git status --short` and `git diff --check`; inspect the complete scoped diff against `origin/master`.
- [x] **Step 4: Commit only scoped files** with `git add` on the two source files, the session test, and these two documents, then `git commit -m "feat: hide PiP actions while typing"`.

Verification note: the full 243-test run has one reproducible WebKit teardown timing failure in the unrelated `CaptureWebViewIntegrationTests.testBundledEditorRunsRealReplyBridgeAndRestoresStashedContentAfterRelaunch`. That test passes in isolation; the remaining 242 tests pass together when it is skipped. All 16 `NotionWebSessionTests` pass.
