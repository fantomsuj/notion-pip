# Intentional Edge-Handle Drops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the stashed edge handle accept one structurally valid Notion page URL, widen inward with an `Open in Perch` preview, and activate the page exactly once only after release.

**Architecture:** A pure domain candidate validates page identity and sanitizes display-only labels. A narrow AppKit pasteboard adapter and drag-session state machine feed the existing handle interaction view. `PiPStashHandleController` owns temporary expansion, local-title upgrades, and recent-shelf suppression; the completed drop travels through an application relay into the existing runtime activation and persistence path.

**Tech Stack:** Swift 6.2, AppKit `NSDraggingDestination`/`NSPasteboard`, SwiftUI `NSViewRepresentable`, SwiftData model actor, XCTest, macOS 14+.

## Global Constraints

- Implement Slice 1 only: one structurally valid Notion page URL. Do not implement text insertion, rich-content reveal, file promises, `.webloc`, multiple items, uploads, a capture outbox, or a local asset store.
- Hover, drag enter/update, label lookup, drag exit, cancellation, and invalid data must never navigate, restore the PiP, record a visit, or activate the application.
- `performDragOperation` is the only direct-drop commit boundary, and one drag sequence can commit at most once.
- `NotionPageReference` remains the sole page-URL authority. A malformed Notion-family URL is rejected and never reinterpreted as ordinary text.
- Accept one pasteboard item only. Prefer its `public.url` representation; fall back to `.string` only when no URL representation exists and the whole trimmed string is one URL.
- The preview label is presentation metadata only. Precedence is local stored title, sanitized `public.url-name`, `NotionPageReference.displayTitle`, then `Notion page`; it never changes canonical URL or page ID.
- Label normalization collapses whitespace, strips Unicode control and bidirectional formatting scalars, returns nil for blank input, and caps at 80 user-perceived characters.
- The resting handle remains 36×96. A valid candidate expands to 260 points wide, stays 96 points high, and stays attached to the same left or right visible-frame edge without changing persisted stash placement.
- Invalid or unsupported drags produce no expansion, error treatment, shelf dismissal, or advertised operation.
- While a valid external drag is active, cancel pending recent-shelf work and suppress new hover/secondary-click shelf requests. Exit/cancel returns to the resting frame.
- The handle advertises `.copy` only when both the candidate is valid and the source operation mask permits copy.
- Keep exactly one Notion `WKWebView`; Slice 1 performs no metadata navigation and creates no metadata WebView.
- Successful drops call `AppRuntime.activate(page:source:)` with `.edgeHandleDrop`, preserving panel restore/replace, shortcut cancellation, page publication, visit persistence, and resolved-title persistence.
- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts. Do not use `@unchecked Sendable`, `nonisolated(unsafe)`, detached tasks, force unwraps, or force casts.
- Use strict red-green-refactor TDD. Every production behavior is preceded by a focused failing test and the failure is recorded in the task report.

---

### Task 1: Validated Drop Candidate, Pasteboard Reader, and Local Title Lookup

**Files:**
- Create: `Sources/Perch/Domain/NotionPageDrop.swift`
- Create: `Sources/Perch/Platform/NotionPageDropPasteboardReader.swift`
- Modify: `Sources/Perch/Persistence/PageRepository.swift`
- Create: `Tests/PerchTests/NotionPageDropTests.swift`
- Create: `Tests/PerchTests/NotionPageDropPasteboardReaderTests.swift`
- Modify: `Tests/PerchTests/PageRepositoryTests.swift`

**Interfaces:**
- Produces: `struct NotionPageDrop: Equatable, Sendable` with `page`, `sourceLabel`, `init(validating:sourceLabel:)`, and `displayLabel(localTitle:)`.
- Produces: `protocol NotionPageDropTitleProviding: Sendable { func displayTitle(for pageID: String) async -> String? }`.
- Produces: `@MainActor enum NotionPageDropPasteboardReader { static func candidate(from pasteboard: NSPasteboard) -> NotionPageDrop? }`.
- `PageRepository` conforms to `NotionPageDropTitleProviding`, preferring active, then pinned, then recent local snapshots for the canonical page ID.

- [ ] **Step 1: Write failing domain tests**

Add literal tests proving valid URL construction; source-label cleanup; removal of control and bidirectional formatting scalars; 80-character cap; and label precedence `local > source > slug > Notion page`. Include malformed ID, HTTP, lookalike host, credentials, and oversized URL rejection through `NotionPageReference`.

- [ ] **Step 2: Run domain tests and record the expected RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionPageDropTests
```

Expected: compilation or assertion failure because `NotionPageDrop` does not exist.

- [ ] **Step 3: Implement the minimal domain candidate**

Use `NotionPageReference(validating:)` for identity. Normalize presentation labels by mapping whitespace, Unicode control categories, `U+061C`, `U+200E–U+200F`, `U+202A–U+202E`, and `U+2066–U+2069` to separators, collapsing separators, and taking the first 80 `Character` values.

- [ ] **Step 4: Run domain tests to GREEN**

Run the Task 1 domain filter and confirm zero failures.

- [ ] **Step 5: Write failing pasteboard-reader tests**

Use uniquely named pasteboards. Prove acceptance of one `.URL` item and one full-string URL fallback, URL-name propagation without pasteboard mutation, URL-over-string precedence, and rejection of no URL, embedded prose, invalid Notion URLs, `.webloc`/file URLs, two pasteboard items, and multiple URL values.

- [ ] **Step 6: Run pasteboard-reader tests and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionPageDropPasteboardReaderTests
```

Expected: failure because the reader does not exist.

- [ ] **Step 7: Implement the minimal pasteboard adapter**

Inspect `pasteboardItems` without writing. Require exactly one item. If that item has `public.url`, validate only that representation; otherwise validate its complete `.string` value. Read `public.url-name` only as a source label.

- [ ] **Step 8: Write failing repository title tests**

Seed active, pinned, and recent snapshots with the same and different canonical IDs. Assert canonical case-insensitive lookup and the category precedence active, pinned, recent; unknown and blank stored titles return nil.

- [ ] **Step 9: Run repository tests and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PageRepositoryTests
```

Expected: failure because the title-provider method is missing.

- [ ] **Step 10: Implement lookup and run Task 1 tests to GREEN**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotionPageDropTests|NotionPageDropPasteboardReaderTests|PageRepositoryTests'
```

- [ ] **Step 11: Commit**

```sh
git add Sources/Perch/Domain/NotionPageDrop.swift Sources/Perch/Platform/NotionPageDropPasteboardReader.swift Sources/Perch/Persistence/PageRepository.swift Tests/PerchTests/NotionPageDropTests.swift Tests/PerchTests/NotionPageDropPasteboardReaderTests.swift Tests/PerchTests/PageRepositoryTests.swift
git commit -m "Add validated Notion page drop candidates"
```

---

### Task 2: Drop Session and Edge-Anchored Expansion Policy

**Files:**
- Create: `Sources/Perch/Platform/NotionPageDropSession.swift`
- Create: `Sources/Perch/Platform/StashHandleDropTargetPolicy.swift`
- Create: `Tests/PerchTests/NotionPageDropSessionTests.swift`
- Create: `Tests/PerchTests/StashHandleDropTargetPolicyTests.swift`

**Interfaces:**
- Consumes: `NotionPageDrop` from Task 1.
- Produces: `struct NotionPageDropSession` with `update(sequenceNumber:candidate:sourceOperationMask:) -> NSDragOperation`, `canPrepare(sequenceNumber:) -> Bool`, `perform(sequenceNumber:) -> NotionPageDrop?`, and `reset()`.
- Produces: `enum StashHandleDropTargetPolicy` with `static let expandedWidth: CGFloat = 260` and `static func expandedFrame(for placement: PanelStashPlacement, visibleFrames: [CGRect]) -> CGRect?`.

- [ ] **Step 1: Write failing session tests**

Prove a new valid copy-capable sequence advertises `.copy`; invalid and source-mask-without-copy advertise none; the candidate freezes for a sequence; prepare only accepts the active sequence; perform returns once and resets; exit/reset clears without returning a drop.

- [ ] **Step 2: Run the session tests and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionPageDropSessionTests
```

- [ ] **Step 3: Implement the minimal session and run GREEN**

Do not invoke callbacks or application APIs in this type. It only owns the frozen candidate and sequence identity.

- [ ] **Step 4: Write failing geometry tests**

Use literal frames to prove a left placement retains `minX`, a right placement retains `maxX`, Y and height remain unchanged, width is 260 when space permits, width clamps to the visible frame on a narrow display, and no matching display returns nil.

- [ ] **Step 5: Run geometry tests and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter StashHandleDropTargetPolicyTests
```

- [ ] **Step 6: Implement policy and run Task 2 tests to GREEN**

Resolve the target display using existing `PanelFramePolicy.targetVisibleFrame`; never return a frame outside its visible bounds and never mutate `PanelStashPlacement`.

- [ ] **Step 7: Commit**

```sh
git add Sources/Perch/Platform/NotionPageDropSession.swift Sources/Perch/Platform/StashHandleDropTargetPolicy.swift Tests/PerchTests/NotionPageDropSessionTests.swift Tests/PerchTests/StashHandleDropTargetPolicyTests.swift
git commit -m "Model edge-handle drop sessions"
```

---

### Task 3: AppKit Drag Destination and Controller-Owned Preview

**Files:**
- Modify: `Sources/Perch/Views/PiPStashHandleView.swift`
- Modify: `Sources/Perch/Platform/PiPStashHandleController.swift`
- Modify: `Tests/PerchTests/PiPStashHandleInteractionTests.swift`
- Modify: `Tests/PerchTests/PiPStashHandleControllerTests.swift`

**Interfaces:**
- Consumes: Task 1 pasteboard reader/title provider and Task 2 session/geometry policy.
- Produces: controller initializer arguments `dropTitleProvider: (any NotionPageDropTitleProviding)? = nil` and `onDropNotionPage: @escaping @MainActor (NotionPageDrop) -> Void = { _ in }`.
- Produces: interaction callbacks `onDropCandidateChanged: @MainActor (NotionPageDrop?) -> Void` and `onDropPerformed: @MainActor (NotionPageDrop) -> Void`.
- Produces: `@MainActor final class PiPStashHandleDropTargetModel: ObservableObject` whose published active state and label drive the existing SwiftUI host without replacing the AppKit interaction view during a drag.

- [ ] **Step 1: Write failing interaction tests**

Exercise the real `PiPStashHandleInteractionView` through a narrow injected snapshot/classification seam. Prove valid enter advertises copy and publishes a candidate without activation; update keeps the frozen candidate; invalid enter advertises none and publishes nothing; prepare/perform publishes exactly one drop; exit/conclude/end clear the preview; mouse click, reposition, pull reveal, right click, and accessibility press remain unchanged.

- [ ] **Step 2: Run interaction tests and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPStashHandleInteractionTests
```

- [ ] **Step 3: Implement the narrow AppKit bridge**

Register `.URL` and `.string`. In `draggingEntered`/`draggingUpdated`, read the candidate and pass it through `NotionPageDropSession`; return the session operation. `prepareForDragOperation` asks the session. `performDragOperation` takes the candidate, clears the target, then invokes `onDropPerformed`. Exit, conclude, and end reset. Never call `NSApp.activate` or restore from these methods.

- [ ] **Step 4: Add failing controller tests**

Prove a valid candidate cancels a delayed shelf load, hides a visible shelf, suppresses hover and secondary-click shelf requests, expands to the Task 2 frame, shows the synchronous source/slug label, upgrades to a local stored title only for the still-active candidate, ignores stale async titles, and collapses on exit. Prove completed drop collapses before forwarding once, and `orderOut` cancels work and makes stale hosted callbacks inert.

- [ ] **Step 5: Run controller tests and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPStashHandleControllerTests
```

- [ ] **Step 6: Implement controller preview and expansion**

The resting view keeps its existing icons. Active content shows `Open in Perch` plus one truncating label line inside the 260×96 material tab. Keep the same side-dependent shape. Use a 0.12-second ease-out frame transition only for production-created panels when Reduce Motion is off; injected test panels and Reduce Motion update immediately. Async title lookup is generation-checked by page ID and candidate identity.

- [ ] **Step 7: Update accessibility behavior**

Resting label/help remain `Restore Perch` and `Bring the stashed Perch back from the side.` During a valid drag, expose `Open <label> in Perch`; clearing returns to the resting semantics. Keep the `Show recent PiP pages` custom action and ordinary accessibility press.

- [ ] **Step 8: Run Task 3 tests and focused regressions to GREEN**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PiPStashHandleInteractionTests|PiPStashHandleControllerTests|PanelStashShelfPolicyTests|PanelStashPolicyTests|PanelPullRevealPolicyTests'
```

- [ ] **Step 9: Commit**

```sh
git add Sources/Perch/Views/PiPStashHandleView.swift Sources/Perch/Platform/PiPStashHandleController.swift Tests/PerchTests/PiPStashHandleInteractionTests.swift Tests/PerchTests/PiPStashHandleControllerTests.swift
git commit -m "Add the edge-handle Notion drop target"
```

---

### Task 4: Runtime Activation, Persistence, and Product Documentation

**Files:**
- Modify: `Sources/Perch/App/AppRuntimeStateTypes.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Tests/PerchTests/RuntimeActivationAndMenuBarTests.swift`
- Modify: `Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift`
- Modify: `README.md`
- Modify: `docs/MANUAL_TEST_MATRIX.md`

**Interfaces:**
- Consumes: `PiPStashHandleController(onDropNotionPage:)` from Task 3.
- Produces: `PageActivationSource.edgeHandleDrop`.
- Produces: internal `NotionPageDropRelay` in `PerchApp.swift`, created before the controller and bound after `AppRuntime` construction to `runtime.activate(page: drop.page, source: .edgeHandleDrop)`.

- [ ] **Step 1: Write failing runtime activation test**

With a stashed current page, activate a different page using `.edgeHandleDrop`. Assert the new active page, `lastActivationSource`, visible presentation, exact committed panel frame restoration, and a single activation through the existing coordinator.

- [ ] **Step 2: Run activation test and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeActivationAndMenuBarTests
```

- [ ] **Step 3: Add source and composition relay**

Wire only completed drops. The relay closure must not be assigned until runtime exists, matching the recent-page selection relay pattern.

- [ ] **Step 4: Write failing persistence test**

Activate through `.edgeHandleDrop`, wait for the repository save, and assert one visit for the dropped page, updated active page, and no save caused by merely constructing or previewing a `NotionPageDrop`.

- [ ] **Step 5: Run persistence test and record RED**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimePinnedPagePersistenceTests
```

- [ ] **Step 6: Complete runtime behavior and run focused GREEN suite**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RuntimeActivationAndMenuBarTests|RuntimePinnedPagePersistenceTests|PinCoordinatorTests|PiPPanelGeometryTests'
```

- [ ] **Step 7: Update user-facing documentation**

Add one README sentence explaining that a valid Notion page link can be dropped on the stashed handle and that hover alone never switches pages. Add manual-matrix rows for Safari/Notion link drags, valid and invalid links, cancellation, both edges/displays, shelf suppression, Reduce Motion, VoiceOver, long/source/slug labels, and already-active-page drops.

- [ ] **Step 8: Run the full verification suite**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Then inspect `git diff --check` and `git status --short`. Do not run or terminate the app unless the user separately approves the repository's setup workflow process check.

- [ ] **Step 9: Commit**

```sh
git add Sources/Perch/App/AppRuntimeStateTypes.swift Sources/Perch/App/PerchApp.swift Tests/PerchTests/RuntimeActivationAndMenuBarTests.swift Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift README.md docs/MANUAL_TEST_MATRIX.md
git commit -m "Route edge-handle drops through Perch"
```

---

## Deferred Slices

- Slice 2: a non-accepting `Continue into <page>` drag-through reveal for a conservative rich-content allowlist, with a natural pointer transition into the single attached `WKWebView`.
- Slice 3: direct text and ordinary-link insertion only after a separate design covers saved-cursor eligibility, async failure receipts, retry, and invalidation.
