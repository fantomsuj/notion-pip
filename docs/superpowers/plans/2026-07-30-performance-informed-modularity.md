# Performance-Informed Modularity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the app's measured responsiveness, WebKit memory behavior, and incremental build isolation by extracting the performance-critical responsibilities identified in the modularity audit.

**Architecture:** First make the user-visible operations observable without recording page or capture content. Then move Quick Capture document preparation and persistence behind a non-UI capability, preserving the current bridge behavior while eliminating redundant JSON canonicalization. Finally, split WebKit retention/restoration from navigation hosting, and introduce SwiftPM targets only for the already-extracted, platform-independent code.

**Tech Stack:** Swift 6.2, macOS 14, AppKit, SwiftUI, WebKit, SwiftData, OSLog/OSSignposter, TypeScript, Node test runner, Swift Package Manager.

## Global Constraints

- Preserve the Swift 6.2, macOS 14, signing, entitlement, public API, and current Quick Capture conflict/recovery behavior.
- Keep every UI and WebKit call on `@MainActor`; move only pure document processing and persistence orchestration off it through `Sendable` values and actors.
- Do not use `Task.detached`, `@unchecked Sendable`, or unsafe/nonisolated concurrency workarounds.
- Do not log capture text, page URLs, Notion titles, identifiers, or document contents; counts, byte sizes, operation names, and success/failure outcomes are permitted.
- Do not change the current 300 ms editor debounce until the baseline trace identifies bridge or persistence work as a material cost.
- Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` for each Swift change. For `Web/QuickCaptureEditor` changes, run `npm test`, `npm run typecheck`, and `npm run build:editor`.

---

## Why these audit findings are performance findings

| Audit finding | Concrete performance consequence | First safe intervention |
| --- | --- | --- |
| `CaptureEditorSession` is a 943-line `@MainActor` class that owns WebKit, bridge decoding, document preparation, persistence flow, recovery, and UI state. | Full capture snapshots are repeatedly decoded and canonicalized while the UI actor coordinates the operation; a large draft can consume event-loop time and makes the critical path opaque. | Measure end-to-end autosave, then move canonicalization and persistence orchestration into a dedicated actor. |
| A `changed` message is emitted after 300 ms of quiet typing and includes the full document. | A sustained edit can serialize, cross the WebKit boundary, validate, and save the whole document roughly three times per second. The repository canonicalizes the same data again. | Keep the reliability contract, instrument payload size/latency, remove duplicate canonicalization, and coalesce only after evidence supports it. |
| `NotionWebSession` is a 1,140-line main-actor type responsible for WebKit lifetime, navigation policy, interaction-state cache, scroll restoration, memory pressure, and editor bridges. | Memory-retention and WebKit-resume behavior cannot be independently measured or tuned; the interaction-state cache retains opaque WebKit objects until a working-set event or memory pressure. | Extract a bounded restoration cache with a memory policy and instrument suspend/resume/eviction. |
| All production Swift code is one executable target. | Architectural dependency violations are conventions, and a small change can recompile the whole app target. | After pure code is extracted, create acyclic local SwiftPM library targets around it. |

The first two items are the highest-leverage runtime work. Module targets are deliberately last: they improve build performance and keep runtime fixes from regressing, but do not themselves make a WebKit action faster.

## Measurement protocol and success criteria

Use a Release build on a representative supported Mac. Record the same five scenarios three times before and after each phase:

1. Cold launch until the app is ready to accept an action.
2. First PiP presentation and first Quick Capture presentation.
3. A 1,000-word paste followed by 20 edits at one-second intervals; record autosave acknowledgement latency and capture bytes.
4. Switch among seven pinned/recent pages, hide the panel for more than 60 seconds, then resume it.
5. Repeat scenario 4 while recording Allocations and the Memory Usage instrument, then generate a memory-pressure event in Instruments.

Acceptance criteria for a phase are:

- No Hangs-instrument finding for the exercised interaction; Apple recommends keeping main-thread work below 100 ms.
- No regression greater than 10% in median or p95 duration for an already-instrumented user operation, unless the change eliminates a documented correctness risk and the trade-off is approved.
- A Quick Capture edit is acknowledged exactly once in source order; save, stash, restore, conflict, and termination recovery behavior remain covered by existing tests.
- On memory pressure while hidden and not typing, the live `WKWebView` and cached interaction states are released; re-showing the panel still restores the durable page state.
- The dependency graph after Task 4 is acyclic and prevents the domain/bridge target from importing AppKit, WebKit, SwiftData, or the app-composition target.

## Research basis

- Apple recommends adding `OSSignposter` intervals and using them to focus Instruments call trees on a user operation: [Recording Performance Data](https://developer.apple.com/documentation/os/recording-performance-data) and [Analyzing CPU profiles with call tree views](https://developer.apple.com/documentation/xcode/analyzing-cpu-profiles-with-call-tree-views).
- Apple’s hang guidance says main-thread work should stay below 100 ms, warns that tasks inherit enclosing actor isolation, and recommends measuring before optimizing: [Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/) and [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
- `WKWebView.evaluateJavaScript` completion returns on the main thread, so WebKit hosting should remain on `@MainActor` while pure processing moves out: [evaluateJavaScript](https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript(_:completionhandler:)).
- Apple recommends local Swift packages to promote modularity and reuse; each target compiles as a module, so target dependencies can enforce the intended direction: [Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages) and [SwiftPM Target](https://developer.apple.com/documentation/packagedescription/target).

## Target dependency model

```text
NotionPiP executable
  ├── NotionPiPPlatform       (AppKit, SwiftUI, WebKit, SwiftData adapters)
  │     └── NotionPiPCapture  (capture application service)
  ├── NotionPiPCapture
  │     └── NotionPiPBridge   (capture message/value contract; Foundation only)
  └── NotionPiPDomain         (value types and policy; Foundation only)
```

`NotionPiPCapture` must not import WebKit. `NotionPiPBridge` must not import AppKit, WebKit, or SwiftData. `NotionPiPPlatform` adapts WebKit and SwiftData to the narrower capabilities the capture service consumes. Do not create targets for UI views or the full persistence layer in this first plan.

### Task 1: Establish traceable, privacy-safe performance baselines

**Files:**
- Modify: `Sources/NotionPiP/Platform/PerformanceSignposter.swift`
- Modify: `Sources/NotionPiP/Platform/AppWindowFactory.swift`
- Modify: `Sources/NotionPiP/Platform/CaptureEditorSession.swift`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Modify: `Tests/NotionPiPTests/PerformanceSignposterTests.swift`
- Create: `docs/PERFORMANCE_BASELINE.md`

**Interfaces:**
- Produces `PerformanceOperation.captureAutosave`, `.notionSessionResume`, `.notionSessionEviction`, and `.notionSessionRestoration`.
- Produces `PerformanceSignposting.begin(_:metadata:)` and `end(_:outcome:)`, where metadata is a `PerformanceMeasurementMetadata` containing only `documentBytes: Int?` and `cacheEntryCount: Int?`.
- Consumes `PerformanceSignposting` through initializer injection; production composition passes `AppPerformanceSignposter.shared` and tests use a spy.

- [ ] **Step 1: Write failing signposter tests for repeated operations and metadata privacy**

Add tests that assert first-presentation operations continue to start once, while `.captureAutosave` can start twice and produces distinct tokens. Add a spy assertion that the metadata carries `documentBytes` but has no `String` payload field.

```swift
func testRepeatedCaptureAutosavesReceiveDistinctIntervals() {
    let signposter = PerformanceSignposterSpy()

    let first = signposter.begin(.captureAutosave, metadata: .init(documentBytes: 1_024))
    signposter.end(first, outcome: .success)
    let second = signposter.begin(.captureAutosave, metadata: .init(documentBytes: 2_048))

    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(signposter.beginCalls.map(\.operation), [.captureAutosave, .captureAutosave])
    XCTAssertEqual(signposter.beginCalls.map(\.metadata.documentBytes), [1_024, 2_048])
}
```

- [ ] **Step 2: Run the focused test and confirm it fails because the operation and metadata API do not exist**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceSignposterTests`

Expected: compile failure referring to `captureAutosave` or `PerformanceMeasurementMetadata`.

- [ ] **Step 3: Add repeatable operation support without weakening first-presentation measurements**

In `PerformanceSignposter.swift`, add a value-only metadata type and make the measurement policy explicit rather than removing `begunOperations` globally.

```swift
struct PerformanceMeasurementMetadata: Equatable, Sendable {
    let documentBytes: Int?
    let cacheEntryCount: Int?

    init(documentBytes: Int? = nil, cacheEntryCount: Int? = nil) {
        self.documentBytes = documentBytes
        self.cacheEntryCount = cacheEntryCount
    }
}

enum PerformanceOperation: String, CaseIterable, Sendable {
    case coldLaunchToReady, firstPiPPresentation, firstQuickCapturePresentation
    case captureAutosave, notionSessionResume, notionSessionEviction, notionSessionRestoration

    var recordsOnlyFirstOccurrence: Bool {
        switch self {
        case .coldLaunchToReady, .firstPiPPresentation, .firstQuickCapturePresentation: true
        case .captureAutosave, .notionSessionResume, .notionSessionEviction, .notionSessionRestoration: false
        }
    }
}
```

Have `AppPerformanceSignposter` begin every repeated operation, retaining the existing once-only behavior for the three startup/presentation intervals. Render metadata using only integers in the signpost message.

- [ ] **Step 4: Instrument complete operations at their ownership boundaries**

Inject `PerformanceSignposting` into `CaptureEditorSession` through `AppWindowFactory`. Wrap the `.changed` request from entry through the repository acknowledgement in a `.captureAutosave` interval using `snapshot.document.count`. In `NotionWebSession`, wrap rehydration from `restoreOrLoad(page:)` to `didFinish`, and wrap `evictWarmWebView()` once it actually retires the hosted web view. End every started interval on success, failure, cancellation, or no-op, so traces have no dangling spans.

- [ ] **Step 5: Add the reproducible baseline guide**

Create `docs/PERFORMANCE_BASELINE.md` with the five scenarios above, exact Instruments template selection (`Time Profiler`, `Hangs`, `os_signpost`, `Allocations`, and `Memory Usage`), the fields to capture, and a result table. State that traces and generated documents are local diagnostic artifacts and must not be committed.

- [ ] **Step 6: Verify the instrumentation**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceSignposterTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass. Then follow `docs/PERFORMANCE_BASELINE.md` once in a Release profile and attach the summarized measurements to the implementation issue, not capture contents or raw browsing data.

- [ ] **Step 7: Commit**

```sh
git add Sources/NotionPiP/Platform/PerformanceSignposter.swift Sources/NotionPiP/Platform/AppWindowFactory.swift Sources/NotionPiP/Platform/CaptureEditorSession.swift Sources/NotionPiP/Platform/NotionWebSession.swift Tests/NotionPiPTests/PerformanceSignposterTests.swift docs/PERFORMANCE_BASELINE.md
git commit -m "perf: instrument capture and web session operations"
```

### Task 2: Move Quick Capture preparation and persistence orchestration off the UI actor

**Files:**
- Create: `Sources/NotionPiP/Services/CaptureDraftPersistenceService.swift`
- Create: `Tests/NotionPiPTests/CaptureDraftPersistenceServiceTests.swift`
- Modify: `Sources/NotionPiP/Platform/CaptureEditorSession.swift`
- Modify: `Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift`
- Modify: `Sources/NotionPiP/Persistence/CaptureRepository.swift`
- Modify: `Tests/NotionPiPTests/CaptureBridgeProtocolTests.swift`
- Modify: `Tests/NotionPiPTests/CaptureWebViewAutosaveTests.swift`

**Interfaces:**
- Consumes `CaptureEditorSnapshot`, `CaptureRepository`, and `CaptureRepositoryError`.
- Produces `actor CaptureDraftPersistenceService` with `save(snapshot:expectedRevision:)`, `saveIfChanged(snapshot:expectedRevision:)`, and `prepareForTermination(snapshot:)`.
- Produces `struct CanonicalCaptureDocument: Equatable, Sendable`, whose only initializer validates and canonicalizes `Data` once.
- `CaptureEditorSession` remains responsible for WebKit calls and published UI state; it delegates only pure validation and repository calls to the service.

- [ ] **Step 1: Write a failing service test that proves one prepared document is persisted unchanged**

Use an in-memory `CaptureRepository` with its existing save hook. Save a large valid capture document through the new service, then assert the stored `editorDocument` equals `CanonicalCaptureDocument.data` and the revision increments once.

```swift
func testSavePersistsPreparedCanonicalDocumentOnce() async throws {
    let repository = try CaptureRepository(inMemory: true)
    let service = CaptureDraftPersistenceService(repository: repository)
    let snapshot = CaptureEditorSnapshot(draftID: "draft", title: "Title", document: largeDocument)

    let saved = try await service.save(snapshot: snapshot, expectedRevision: 0)

    XCTAssertEqual(saved.revision, 1)
    XCTAssertEqual(try await repository.draft(id: "draft")?.editorDocument,
                   try CanonicalCaptureDocument(validating: largeDocument).data)
}
```

- [ ] **Step 2: Run the focused service test and confirm it fails because the capability does not exist**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CaptureDraftPersistenceServiceTests`

Expected: compile failure referring to `CaptureDraftPersistenceService` or `CanonicalCaptureDocument`.

- [ ] **Step 3: Introduce the validated document value and a repository entry point that accepts it**

Move canonicalization behind this value type. Keep the existing `saveDraft(_:,expectedRevision:)` for untrusted/general callers; add a separate internal entry point for data already validated by the bridge service.

```swift
struct CanonicalCaptureDocument: Equatable, Sendable {
    let data: Data

    init(validating data: Data) throws {
        self.data = try CaptureBridgeProtocol.canonicalDocument(data)
    }
}

struct PreparedDraftMutation: Sendable {
    let id: String
    let title: String
    let document: CanonicalCaptureDocument
    let sourceDocument: Data?
    let disposition: DraftDisposition
}
```

`CaptureRepository.savePreparedDraft(_:, expectedRevision:)` must validate identifiers, revisions, and dispositions exactly as `saveDraft` does, but use `mutation.document.data` directly instead of canonicalizing it a second time. The general method continues to canonicalize raw data, preserving its existing boundary.

- [ ] **Step 4: Implement the capture application service as an actor**

`CaptureDraftPersistenceService` owns the fetch/compare/save sequence now duplicated in `CaptureEditorSession`. It runs on its actor executor, sends only `Sendable` snapshots to the model actor, and returns `CaptureDraftSnapshot` or the existing typed repository error. It must not import AppKit or WebKit.

```swift
actor CaptureDraftPersistenceService {
    private let repository: CaptureRepository

    init(repository: CaptureRepository) { self.repository = repository }

    func save(
        snapshot: CaptureEditorSnapshot,
        expectedRevision: Int
    ) async throws -> CaptureDraftSnapshot {
        let document = try CanonicalCaptureDocument(validating: snapshot.document)
        return try await repository.savePreparedDraft(
            PreparedDraftMutation(
                id: snapshot.draftID,
                title: snapshot.title,
                document: document,
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: expectedRevision
        )
    }
}
```

Implement the other two methods with the existing semantic rules: no write when the stored title/document match, retry one stale revision during termination, and never write an abandoned draft.

- [ ] **Step 5: Replace only persistence calls in `CaptureEditorSession`**

Construct the service in the session initializer. Replace `mutation`, `persistSuppliedSnapshot`, and `persistTerminationSnapshot` with service calls. Retain `latestSnapshot()`, `WKNavigationDelegate`, state-transition receipt logic, conflict presentation, and every `@Published` assignment in the session; those remain the WebKit/UI adapter.

- [ ] **Step 6: Add regression tests and verify JS bridge compatibility**

Add a Swift test using a document close to `CaptureBridgeProtocol.maximumMessageBytes` that asserts validation failure is returned without a repository write. Keep TypeScript `protocol.test.ts` unchanged except for a regression test that full snapshots still produce the same `changed` wire message. Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CaptureDraftPersistenceServiceTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CaptureWebViewAutosaveTests
npm test
npm run typecheck
npm run build:editor
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass, and the end-to-end autosave trace shows no extra bridge request or persistence write relative to the Task 1 baseline.

- [ ] **Step 7: Commit**

```sh
git add Sources/NotionPiP/Services/CaptureDraftPersistenceService.swift Sources/NotionPiP/Platform/CaptureEditorSession.swift Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift Sources/NotionPiP/Persistence/CaptureRepository.swift Tests/NotionPiPTests/CaptureDraftPersistenceServiceTests.swift Tests/NotionPiPTests/CaptureBridgeProtocolTests.swift Tests/NotionPiPTests/CaptureWebViewAutosaveTests.swift Web/QuickCaptureEditor
git commit -m "perf: isolate capture draft persistence"
```

### Task 3: Give WebKit retention and restoration a bounded, measurable owner

**Files:**
- Create: `Sources/NotionPiP/Platform/NotionPageRestorationCache.swift`
- Create: `Tests/NotionPiPTests/NotionPageRestorationCacheTests.swift`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Modify: `Tests/NotionPiPTests/NotionWebSessionTests.swift`
- Modify: `Tests/NotionPiPTests/RuntimePinnedPagePersistenceTests.swift`

**Interfaces:**
- Produces `@MainActor final class NotionPageRestorationCache` owning opaque interaction states, durable restorations, scroll snapshots, and their retain/evict policy.
- `NotionWebSession` consumes `NotionPageRestorationCache` but remains the sole `WKWebView` host and navigation delegate.
- The cache has no WebKit imports in its public API: opaque interaction state is accepted as `Any` but never exposed except to the caller who provided it.

- [ ] **Step 1: Write failing bounded-cache tests**

Test the three retention paths: (a) a working-set update drops interaction state for pages outside the supplied ID set, (b) memory pressure clears every opaque interaction state but retains durable restoration records, and (c) consuming an interaction state removes it so it cannot keep a WebKit page alive.

```swift
@MainActor
func testMemoryPressureDropsOpaqueInteractionStateButKeepsDurableRestoration() throws {
    let cache = NotionPageRestorationCache()
    let restoration = try DurablePageRestoration(/* valid fixed values */)
    cache.storeInteractionState(NSObject(), for: "page-a")
    cache.storeDurableRestoration(restoration)

    cache.handleMemoryPressure()

    XCTAssertNil(cache.takeInteractionState(for: "page-a"))
    XCTAssertEqual(cache.durableRestoration(for: "page-a"), restoration)
}
```

- [ ] **Step 2: Run the focused test and confirm it fails because the cache type does not exist**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionPageRestorationCacheTests`

Expected: compile failure referring to `NotionPageRestorationCache`.

- [ ] **Step 3: Implement the cache and make its memory policy explicit**

Move the three dictionaries from `NotionWebSession` into the cache. Provide `store`, `take`, `durableRestoration`, `scrollSnapshot`, `retain(only:)`, `removeAllInteractionStates()`, and `remove(pageID:)` operations. Normalize every page ID to lowercase in one private helper. `handleMemoryPressure()` removes opaque interaction states immediately but leaves durable, small value snapshots for correct resume behavior.

- [ ] **Step 4: Adapt `NotionWebSession` without changing navigation semantics**

Replace direct dictionary access with cache operations in `activate`, `reloadPinnedPage`, `restoreOrLoad`, `captureAndTearDown`, renderer termination, and `evictInteractionSnapshots(retaining:)`. Keep `WKWebView` creation, `interactionStateReader/writer`, URL observation, navigation decisions, and the 60-second warm-retention timer in `NotionWebSession`.

Use Task 1 signposts to report the cache’s entry count for eviction and resume. A memory-pressure event must first evict the warm web view when the existing safety conditions hold, then clear opaque cache state.

- [ ] **Step 5: Run cache/session/regression tests and inspect a memory trace**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionPageRestorationCacheTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimePinnedPagePersistenceTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Then repeat measurement scenarios 4 and 5. Acceptance is that WebKit interaction state is absent after hidden-memory-pressure eviction and a durable restore still works; do not claim a memory saving merely because RSS shifts in one trace.

- [ ] **Step 6: Commit**

```sh
git add Sources/NotionPiP/Platform/NotionPageRestorationCache.swift Sources/NotionPiP/Platform/NotionWebSession.swift Tests/NotionPiPTests/NotionPageRestorationCacheTests.swift Tests/NotionPiPTests/NotionWebSessionTests.swift Tests/NotionPiPTests/RuntimePinnedPagePersistenceTests.swift
git commit -m "perf: isolate WebKit restoration retention"
```

### Task 4: Enforce the extracted boundaries with local SwiftPM targets

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NotionPiPDomain/` by moving selected pure domain files from `Sources/NotionPiP/Domain/`
- Create: `Sources/NotionPiPBridge/` by moving `CaptureBridgeProtocol.swift` and its Foundation-only contract types
- Create: `Sources/NotionPiPCapture/` by moving `CaptureDraftPersistenceService.swift` and its Foundation-only dependencies
- Modify: imports in moved files and their consumers
- Modify: `Tests/NotionPiPTests/*` imports and target dependencies as required

**Interfaces:**
- `NotionPiPDomain` exports pure values/policies including `CaptureSnapshot`, `DeliveryState`, `RetryPolicy`, and `JSONValue`.
- `NotionPiPBridge` depends on `NotionPiPDomain` and exports the capture request/reply contract plus canonical document validation.
- `NotionPiPCapture` depends on `NotionPiPBridge` and a narrowly defined `CaptureDraftPersisting` protocol; its SwiftData adapter remains in the executable/platform target.
- `NotionPiP` executable depends on all three libraries and owns AppKit, SwiftUI, WebKit, and SwiftData.

- [ ] **Step 1: Write a manifest-level build test by compiling the new targets independently**

Before moving production files, add the manifest targets with placeholder-free source assignments and run each target build. The expected initial failure is missing imports/types, not test discovery changes.

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --target NotionPiPDomain
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --target NotionPiPBridge
```

- [ ] **Step 2: Extract only Foundation-only files and declare acyclic dependencies**

Use this manifest shape; retain the executable target path until a later UI migration.

```swift
.target(name: "NotionPiPDomain", path: "Sources/NotionPiPDomain"),
.target(name: "NotionPiPBridge", dependencies: ["NotionPiPDomain"], path: "Sources/NotionPiPBridge"),
.target(name: "NotionPiPCapture", dependencies: ["NotionPiPBridge"], path: "Sources/NotionPiPCapture"),
.executableTarget(
    name: "NotionPiP",
    dependencies: ["NotionPiPDomain", "NotionPiPBridge", "NotionPiPCapture"],
    path: "Sources/NotionPiP",
    resources: [.copy("Resources/QuickCapture")]
)
```

If an extracted source imports AppKit, WebKit, SwiftData, or a platform file, leave it in the executable target and create a narrow protocol/value type instead. Do not solve a cycle by giving a lower target a platform dependency.

- [ ] **Step 3: Replace concrete capture persistence access with a capability protocol**

Define `CaptureDraftPersisting` in `NotionPiPCapture` using the exact operations the service needs, then make `CaptureRepository` conform in the executable target extension. This keeps the service testable with an in-memory fake without giving it the entire SwiftData repository.

```swift
protocol CaptureDraftPersisting: Sendable {
    func draft(id: String) async throws -> CaptureDraftSnapshot?
    func savePreparedDraft(
        _ mutation: PreparedDraftMutation,
        expectedRevision: Int
    ) async throws -> CaptureDraftSnapshot
}
```

- [ ] **Step 4: Add dependency-boundary tests through isolated builds**

Run each target in isolation and the full suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --target NotionPiPDomain
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --target NotionPiPBridge
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --target NotionPiPCapture
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: the domain, bridge, and capture targets compile without AppKit/WebKit/SwiftData imports, and all existing tests still pass. Capture before/after clean-build wall-clock times as a secondary metric; the architectural boundary is the primary acceptance criterion.

- [ ] **Step 5: Update the modularity audit and performance baseline summary**

Record the actual trace results, changes to p50/p95, observed cache behavior, and the final target graph in the audit document. Explicitly mark any optimization that did not improve a measured metric as rejected or deferred rather than presenting it as a win.

- [ ] **Step 6: Commit**

```sh
git add Package.swift Sources/NotionPiPDomain Sources/NotionPiPBridge Sources/NotionPiPCapture Sources/NotionPiP Tests/NotionPiPTests docs
git commit -m "refactor: enforce capture module boundaries"
```

## Deferred work

- Delta-based Quick Capture bridge messages. The current full-snapshot protocol is simpler and supports recovery; only investigate deltas if Task 1 proves that snapshot byte size or serialization dominates autosave latency.
- Splitting every UI view or all SwiftData repositories into targets. These changes have a lower runtime payoff and would create churn before the capture/WebKit boundaries are stable.
- Changing WebKit process-pool configuration. Apple documents that creating multiple `WKProcessPool` instances no longer has an effect, so it is not a credible optimization path.
