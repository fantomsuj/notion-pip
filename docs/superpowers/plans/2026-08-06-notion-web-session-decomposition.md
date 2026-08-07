# Notion Web Session Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose `NotionWebSession` into focused navigation, page-restoration, and script-message collaborators without changing observable behavior.

**Architecture:** Keep `NotionWebSession` as the sole `WKWebView` owner and WebKit delegate adapter. Move pure decisions into a Foundation policy, opaque page continuity records into an `@MainActor` coordinator that never retains WebKit, and bridge installation/generation into an `@MainActor` coordinator that forwards validated messages back to the session.

**Tech Stack:** Swift 6.2, macOS 14, AppKit, Combine, WebKit, XCTest, Swift Package Manager.

## Global Constraints

- Preserve Swift 6.2, macOS 14, signing, entitlements, and the existing public API.
- Preserve signed-in session continuity, one-WebView identity, URL validation, external routing, retained selection, scroll fallback, reload/re-pin behavior, renderer recovery, and every failure banner.
- Keep all WebKit and UI work on `@MainActor`; do not add unsafe concurrency escapes.
- Retain delegate callback ordering in `NotionWebSession` and use identity plus monotonically increasing generations to reject stale callbacks.
- Validate with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

---

### Task 1: Extract deterministic navigation policy

**Files:**
- Create: `Sources/NotionPiP/Platform/NotionWebNavigationPolicy.swift`
- Create: `Tests/NotionPiPTests/NotionWebNavigationPolicyTests.swift`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Modify: `Tests/NotionPiPTests/WebNavigationDestinationTests.swift`

**Interfaces:**
- Produces `NotionWebNavigationPolicy.actionDecision(for:targetFrameIsPresent:) -> NotionWebNavigationActionDecision`.
- Produces `NotionWebNavigationPolicy.newWindowDecision(for:) -> NotionWebNewWindowDecision`.
- Produces `NotionWebNavigationPolicy.failureDecision(for:) -> NotionWebNavigationFailureDecision`.
- `NotionWebSession` consumes decisions and performs the existing `openURL`, `loadRequest`, state publication, and WebKit return-value effects.

- [ ] **Step 1: Write direct policy tests before production code**

Cover targetless deferral, trusted allow, external open-and-cancel, unsupported cancel, trusted/external/unsupported new-window decisions, cancellation, every offline error code, and the generic banner literal.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebNavigationPolicyTests`

Expected: compile failure because `NotionWebNavigationPolicy` and its decision types do not exist.

- [ ] **Step 3: Implement the policy and adapt delegate entry points**

Implement app-owned enums with associated `URL` or `URLRequest` values. Map decisions inside `NotionWebSession.navigationPolicy`, `handleNewWindowRequest`, and both failure callbacks without moving callback order or side effects.

- [ ] **Step 4: Run policy and existing navigation tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotionWebNavigationPolicyTests|WebNavigationDestinationTests|NotionWebSessionTests'`

Expected: all selected tests pass.

### Task 2: Extract page-state restoration coordination

**Files:**
- Create: `Sources/NotionPiP/Platform/NotionPageStateRestorationCoordinator.swift`
- Create: `Tests/NotionPiPTests/NotionPageStateRestorationCoordinatorTests.swift`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Modify: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Produces `NotionPageStateRestorationCoordinator.RestorationPlan`, with `.interactionState(Any)` and `.load(url:isDurableRestoration:)` cases.
- Produces activation, reload, load-recording, scroll-recording, capture, navigation-finish, durable-failure-fallback, page-resolution, eviction, and renderer-termination methods that accept values but never a `WKWebView`.
- `NotionWebSession` continues to read/write `WKWebView.interactionState`, load URLs, apply scroll, emit captured restorations, and own performance intervals.

- [ ] **Step 1: Write direct coordinator tests before production code**

Use literal page IDs, URLs, scroll values, opaque sentinel objects, and injected dates to prove LRU capacity, one-shot interaction restoration, page-matched saved URL selection, validated durable capture, pending scroll consumption, single canonical fallback, and explicit reset behavior.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionPageStateRestorationCoordinatorTests`

Expected: compile failure because the coordinator and plan do not exist.

- [ ] **Step 3: Implement the coordinator and replace session dictionaries/flags**

Move `NotionInteractionStateCache` with the coordinator. Replace direct dictionary and saved-URL mutation in activation, reload, load, page switching, restoration, navigation finish/failure, page resolution, memory pressure, and renderer termination with narrow coordinator calls.

- [ ] **Step 4: Run restoration and session tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotionPageStateRestorationCoordinatorTests|NotionWebSessionTests|NotionWebLifecycleControllerTests'`

Expected: all selected tests pass.

### Task 3: Extract script-message coordination and generations

**Files:**
- Create: `Sources/NotionPiP/Platform/NotionWebScriptMessageCoordinator.swift`
- Create: `Tests/NotionPiPTests/NotionWebScriptMessageCoordinatorTests.swift`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Modify: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Produces `NotionWebScriptMessageCoordinator.install(in:) -> UInt`, `remove(from:)`, `generation`, and a weak `delegate` conforming to `NotionWebScriptMessageHandling`.
- Moves `NotionEditorActivityBridge`, `NotionScrollBridge`, their scripts, the caret script installation, and the three weak handlers into the coordinator file.
- `NotionWebSession` receives validated activity, scroll, and caret values with the source WebView and generation, then applies its existing identity checks and lifecycle/UI effects.

- [ ] **Step 1: Write direct coordinator tests before production code**

Assert installation returns increasing generations, installs three main-frame document-start scripts, and removal advances the generation while clearing scripts and handlers through an injected remover.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebScriptMessageCoordinatorTests`

Expected: compile failure because `NotionWebScriptMessageCoordinator` does not exist.

- [ ] **Step 3: Implement coordinator and keep the session as adapter**

Install through the coordinator during `configure`, capture its returned generation in the URL observation, remove through it during `retire`, and compare incoming generations through the coordinator. Do not transfer WebView ownership or delegate conformance.

- [ ] **Step 4: Run all bridge and session tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotionWebScriptMessageCoordinatorTests|NotionWebSessionTests|NotionEditorCaretBridgeTests|NotionEditorSelectionTests'`

Expected: all selected tests pass.

### Task 4: Verify timing, behavior, and integration

**Files:**
- Modify only files required by failures found during verification.

**Interfaces:**
- Consumes all three collaborators through `NotionWebSession`.
- Produces no new behavior; this task closes compatibility and timing gaps.

- [ ] **Step 1: Run timing-sensitive suites five consecutive times**

Run a loop over `NotionWebSessionTests`, `NotionEditorSelectionTests`, `NotionEditorCaretBridgeTests`, and `WebNavigationDestinationTests`, stopping on the first failure.

- [ ] **Step 2: Run the full Swift suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 3: Review the diff against every design constraint**

Inspect `git diff origin/master...HEAD` and verify the session remains the sole live WebView owner and both WebKit delegates, no unsafe concurrency annotations were added, all failure text and routing effects remain unchanged, and each new collaborator owns coherent state rather than forwarded methods.

- [ ] **Step 4: Commit the implementation**

Stage only the documented source, test, and design/plan files. Commit with `Decompose Notion web session responsibilities`.
