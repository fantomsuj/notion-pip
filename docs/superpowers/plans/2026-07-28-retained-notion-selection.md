# Retained Notion Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore keyboard focus and the prior DOM selection when a stashed Notion PiP panel reuses the same in-memory web view.

**Architecture:** `NotionWebSession` owns a page-scoped selection snapshot and a generation token for pending capture work. An injected selection evaluator executes one-shot capture and restore operations in the trusted Notion main frame, while an injected attachment scheduler makes focus and restoration testable after the retained web view is re-hosted.

**Tech Stack:** Swift 6.2, AppKit, WebKit, XCTest, macOS 14 public APIs

## Global Constraints

- Preserve the existing macOS 14 deployment target, public API, signing, and entitlement contracts.
- Capture only from a live content-editable element in a trusted Notion main frame.
- Never persist the selection across a new web view or fresh page load.
- Keep JavaScript failures, malformed results, and stale DOM paths silent and use ordinary web-view focus as the fallback.
- Preserve all unrelated worktree changes, including the in-progress re-pin/reload behavior.

---

### Task 1: Define and decode one-shot selection operations

**Files:**
- Create: `Sources/NotionPiP/Platform/NotionEditorSelection.swift`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Test: `Tests/NotionPiPTests/NotionEditorSelectionTests.swift`
- Test: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Produces: `NotionEditorSelectionSnapshot`, `NotionEditorSelectionEvaluation.capture`, and `NotionEditorSelectionEvaluation.restore(snapshot)`
- Produces: an injected evaluator closure that returns raw JavaScript values through `Result<Any?, Error>`

- [x] **Step 1: Write failing tests for valid, missing, malformed, and failed capture results**

Add lifecycle tests whose injected evaluator completes capture with a valid literal dictionary, `nil`, malformed data, or an error. Assert on whether a restore operation is requested, not on JavaScript source text.

- [x] **Step 2: Run the focused tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests
```

Expected: compilation or assertion failure because selection operations and evaluator injection do not exist.

- [x] **Step 3: Add the minimal snapshot parser and JavaScript operations**

Add value-semantic snapshot types with bounded nonnegative DOM paths and offsets. Implement capture JavaScript that:

- requires the active selection and active element to share one connected `[contenteditable]` root;
- records that root's document path and both endpoints relative to it;
- marks the editable root with a random one-shot identity token.

Implement restore JavaScript that resolves and validates the same marked root, reconstructs both endpoints, focuses it, and applies `Selection.setBaseAndExtent`.

- [x] **Step 4: Run the focused tests and verify GREEN**

Run the same filtered test command and require exit code 0.

### Task 2: Integrate capture, suspension, focus, and restore

**Files:**
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Test: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: selection operations from Task 1
- Produces: `panelDidHide()` capture-before-suspend behavior and `panelDidShow()` focus-after-attachment behavior

- [x] **Step 1: Write failing retained-page lifecycle tests**

Cover:

- capture completion suspends and stores only while the panel remains hidden;
- showing the panel before capture completes prevents later suspension and storage;
- restoring the matching retained page focuses first and requests exactly one restore;
- missing, malformed, or failed capture focuses without requesting restore.

- [x] **Step 2: Run the focused tests and verify RED**

Run the filtered `NotionWebSessionTests` command and confirm failures identify the missing lifecycle behavior.

- [x] **Step 3: Implement minimal lifecycle state**

Add a capture generation, a page-scoped saved snapshot, a focus closure, and a post-attachment scheduler. Delay detachment only while a trusted active-page capture is pending. On show, invalidate pending capture, resume the retained view, schedule ordinary focus, consume any matching snapshot, and then issue the restore operation.

- [x] **Step 4: Run the focused tests and verify GREEN**

Run the filtered command and require exit code 0.

### Task 3: Invalidate stale selection state

**Files:**
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Test: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: page-scoped saved snapshot and generation from Task 2
- Produces: invalidation on navigation, reload, resolved SPA page changes, explicit page replacement, and web-view eviction

- [x] **Step 1: Write failing invalidation tests**

Capture a valid snapshot, trigger each invalidating lifecycle event, show the panel, and assert that focus occurs but no restore operation is evaluated. Include a navigation event while capture is pending to prove the hidden web view still suspends after cancellation.

- [x] **Step 2: Run the focused tests and verify RED**

Run the filtered command and confirm stale restore requests or missing suspension cause the expected failures.

- [x] **Step 3: Add focused invalidation calls**

Clear the snapshot and advance the generation before every fresh load/reload, page identity change, navigation start, resolved SPA page adoption, and eviction. If invalidation cancels an in-flight capture while hidden, suspend the view immediately.

- [x] **Step 4: Run the focused tests and verify GREEN**

Run the filtered command and require exit code 0.

### Task 4: Verify the integrated change

**Files:**
- Review: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Review: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

- [x] **Step 1: Review the final diff against the approved design**

Confirm capture is main-frame-only, page-scoped, one-shot, nonpersistent, and silent on all fallback paths. Confirm the existing opaque interaction-state restoration remains unchanged.

- [x] **Step 2: Check formatting and whitespace**

Run:

```sh
git diff --check
```

Expected: no output and exit code 0.

- [x] **Step 3: Run the full Swift test suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass with exit code 0.
