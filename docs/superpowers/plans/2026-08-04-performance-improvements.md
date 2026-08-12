# Perch Performance Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce capture-history I/O and Quick Capture document work, add measurements at usable-state boundaries, and remove avoidable WebView/UI work.

**Architecture:** SwiftData exposes narrowly scoped metadata queries and the UI consumes a blob-free summary type. Quick Capture transports a validated canonical document value so persistence does not repeatedly parse and serialize the same JSON, while performance intervals explicitly distinguish first-only and repeatable operations. WebKit interaction state becomes a bounded LRU, window construction becomes lazy, and the editor guards redundant overlay DOM mutations.

**Tech Stack:** Swift 6.2, SwiftData, AppKit/SwiftUI, WebKit, OSLog signposts, TypeScript/Tiptap, XCTest, Vitest.

## Global Constraints

- Preserve macOS 14 deployment, Swift 6.2 concurrency safety, public APIs, signing, and entitlements.
- Keep the Quick Capture autosave debounce at 300 ms.
- Cap cached WebKit interaction states at the 14-page working set.
- Do not fetch editor/source document blobs for the outbox summary list.
- Validate native work with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- When JavaScript dependencies are installed, validate with `npm test`, `npm run typecheck`, and `npm run build:editor` in `Web/QuickCaptureEditor`.

---

### Task 1: Targeted capture persistence queries

**Files:**
- Modify: `Sources/Perch/Domain/CaptureSnapshot.swift`
- Modify: `Sources/Perch/Persistence/CaptureRepository.swift`
- Modify: `Sources/Perch/Services/CapturePersistencePorts.swift`
- Modify: `Sources/Perch/Services/DeliveryScheduler.swift`
- Modify: `Sources/Perch/App/AppRuntime.swift`
- Modify: `Sources/Perch/Views/CaptureOutboxStatusView.swift`
- Test: `Tests/PerchTests/CaptureRepositoryTests.swift`
- Test: `Tests/PerchTests/DeliverySchedulerTests.swift`

**Interfaces:**
- Produces: `activeDraft()`, `nextRetryDate()`, and `recentRecordSummaries(limit:)` repository operations.
- Produces: `CaptureRecordSummary`, containing only outbox presentation metadata.

- [ ] Add failing tests proving active-draft selection, earliest retry selection, descending limited summaries, and scheduler use of retry metadata.
- [ ] Run the focused tests and confirm failures are caused by the missing targeted interfaces.
- [ ] Implement predicate/sort/fetch-limit descriptors and summary mapping without document fields.
- [ ] Replace full-history consumers and remove startup outbox loading.
- [ ] Run the focused tests and confirm they pass.

### Task 2: Single canonical Quick Capture document

**Files:**
- Modify: `Sources/Perch/Domain/CaptureSnapshot.swift`
- Modify: `Sources/Perch/Platform/CaptureBridgeProtocol.swift`
- Modify: `Sources/Perch/Platform/WeakScriptMessageHandler.swift`
- Modify: `Sources/Perch/Platform/CaptureEditorSession.swift`
- Modify: `Sources/Perch/Persistence/CaptureRepository.swift`
- Test: `Tests/PerchTests/CaptureBridgeProtocolTests.swift`
- Test: `Tests/PerchTests/CaptureEditorFlowTests.swift`
- Test: `Tests/PerchTests/CaptureRepositoryTests.swift`

**Interfaces:**
- Produces: a validated `CanonicalCaptureDocument` sendable value whose initializer performs the one native canonicalization pass.
- Consumes: repository mutations carrying that value rather than unvalidated editor `Data`.

- [ ] Add failing tests proving bridge decoding produces a validated canonical value and persistence does not recanonicalize it.
- [ ] Run the focused tests and confirm expected failures.
- [ ] Decode WebKit message objects directly, canonicalize the nested document once, and pass the value through session mutations.
- [ ] Keep stored-data validation when reading legacy/corrupt persistence and reply encoding.
- [ ] Run the focused tests and confirm they pass.

### Task 3: Ready-state and repeatable performance intervals

**Files:**
- Modify: `Sources/Perch/Platform/PerformanceSignposter.swift`
- Modify: `Sources/Perch/Platform/CaptureEditorSession.swift`
- Modify: `Sources/Perch/Platform/NotionWebSession.swift`
- Test: `Tests/PerchTests/PerformanceSignposterTests.swift`
- Test: `Tests/PerchTests/CaptureEditorFlowTests.swift`
- Test: `Tests/PerchTests/NotionWebSessionTests.swift`

**Interfaces:**
- Produces: explicit first-only versus repeatable operation policy.
- Produces: repeatable Quick Capture ready/autosave, Notion restoration, and WebView eviction measurements with byte/cache counts.

- [ ] Add failing tests for duplicate first-only suppression and concurrent/sequential repeatable intervals.
- [ ] Run focused tests and confirm expected failures.
- [ ] Implement interval policy, metadata-bearing end calls, and ready/autosave/restoration/eviction call sites.
- [ ] Run focused tests and confirm they pass.

### Task 4: Bounded interaction-state LRU and fixed toolbar overlay

**Files:**
- Modify: `Sources/Perch/Platform/NotionWebSession.swift`
- Modify: `Sources/Perch/Views/PiPChromeView.swift`
- Test: `Tests/PerchTests/NotionWebSessionTests.swift`
- Test: `Tests/PerchTests/PiPChromeViewTests.swift`

**Interfaces:**
- Produces: a 14-entry recency-ordered opaque interaction-state cache.
- Produces: a constant-height WebView host with toolbar appearance animated only by opacity/offset.

- [ ] Add failing tests for LRU eviction/recency and constant toolbar layout reservation.
- [ ] Run focused tests and confirm expected failures.
- [ ] Implement the bounded cache and fixed overlay toolbar.
- [ ] Run focused tests and confirm they pass.

### Task 5: Lazy secondary windows

**Files:**
- Modify: `Sources/Perch/Platform/SettingsWindowPresenter.swift`
- Modify: `Sources/Perch/Platform/PageURLInputPresenter.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Test: `Tests/PerchTests/AppWindowPresenterTests.swift`
- Test: `Tests/PerchTests/PageURLInputPresenterTests.swift`

**Interfaces:**
- Produces: presenter factories that construct Settings and Pin Page windows on first presentation and retain them thereafter.

- [ ] Add failing tests proving construction is deferred, hide does not construct, and repeated show reuses one window.
- [ ] Run focused tests and confirm expected failures.
- [ ] Implement lazy construction using the existing presenter pattern.
- [ ] Run focused tests and confirm they pass.

### Task 6: Guard redundant editor overlay DOM work

**Files:**
- Modify: `Web/QuickCaptureEditor/quick-capture-editor-controller.ts`
- Modify: `Web/QuickCaptureEditor/controllers/slash-menu-controller.ts`
- Test: `Web/QuickCaptureEditor/quick-capture-editor-controller.test.ts`
- Test: `Web/QuickCaptureEditor/controllers/slash-menu-controller.test.ts`
- Generated: `Sources/Perch/Resources/QuickCapture/editor.js`

**Interfaces:**
- Produces: transaction-aware overlay refresh and idempotent slash-menu close.

- [ ] Add failing DOM tests proving already-closed menus are untouched and selection-only/document-only transactions refresh only relevant overlays.
- [ ] Run the focused npm tests and confirm expected failures.
- [ ] Add state guards and transaction relevance checks.
- [ ] Run npm tests/typecheck, rebuild the checked-in editor asset, and confirm they pass.

### Task 7: Full verification

**Files:**
- Review all changed files against this plan and the attached audit.

- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` and confirm zero failures.
- [ ] Run the JavaScript test/typecheck/build commands when dependencies are available.
- [ ] Inspect `git diff --check`, `git status --short`, and `git diff origin/master...` for unintended changes.
- [ ] Report delivered improvements and any validation that could not be performed.
