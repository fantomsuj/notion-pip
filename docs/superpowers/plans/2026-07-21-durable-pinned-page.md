# Durable Pinned Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the one active Notion page and automatically show it in the PiP panel after the app relaunches.

**Architecture:** A shared SwiftData `ModelContainer` at the composition root backs both capture and page repositories. `PageRepository` exposes a narrow single-current-page interface, while `AppRuntime` restores once at startup and serializes non-blocking persistence writes in activation order. The panel remains an in-memory presentation concern and receives restored pages through its existing show path.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, SwiftData, XCTest, Swift Package Manager

## Global Constraints

- A saved page always auto-shows at launch, regardless of whether the PiP was visible when the app quit.
- Persist the canonical page reference only; do not serialize WebView history, scroll position, form state, or unsaved edits.
- Persistence failures must never hide or remove the active in-memory PiP.
- A direct activation that arrives during asynchronous restore must win.
- Do not log full Notion URLs or tokens.
- Preserve the existing default `WKWebsiteDataStore` behavior.
- Leave unrelated worktree changes untouched and stage only files named by each task.

---

### Task 1: Single-current-page persistence boundary

**Files:**
- Create: `Sources/Perch/Persistence/PerchPersistence.swift`
- Modify: `Sources/Perch/Persistence/CaptureRepository.swift`
- Modify: `Sources/Perch/Persistence/PageRepository.swift`
- Modify: `Tests/PerchTests/PageRepositoryTests.swift`

**Interfaces:**
- Produces: `PerchPersistence.makeContainer(storeURL:inMemory:) throws -> ModelContainer`
- Produces: `PinnedPagePersisting.currentPinnedPage() async throws -> StoredPageSnapshot?`
- Produces: `PinnedPagePersisting.replaceCurrent(with:) async throws -> StoredPageSnapshot`
- Produces: `CaptureRepository.init(container:clock:beforeHelperFetch:)`

- [ ] **Step 1: Add failing repository tests for replacement, reopen, rollback, and corrupt storage**

Extend `PageRepositoryTests` with tests that create an in-memory or temporary on-disk container, call `replaceCurrent(with:)`, and assert:

```swift
let first = try page(slug: "First", id: firstPageID)
let second = try page(slug: "Second", id: secondPageID)
_ = try await repository.replaceCurrent(with: first)
_ = try await repository.replaceCurrent(with: second)

let current = try await repository.currentPinnedPage()
XCTAssertEqual(current?.pageID, secondPageID)
XCTAssertEqual(try await repository.pinnedPages().map(\.pageID), [secondPageID])
```

For reopen, release the first container/repository, recreate them against the same temporary `storeURL`, and assert the canonical URL and page ID survive. For corruption, insert a `PinnedPageModel` with `canonicalURL: "not a Notion URL"` through a `ModelContext` and assert `currentPinnedPage()` throws `CaptureRepositoryError.invalidStoredValue`. Keep the existing injected-save-failure test and update it to the new replacement API so it proves rollback leaves the previous selection intact.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PageRepositoryTests
```

Expected: compilation fails because `replaceCurrent(with:)`, `currentPinnedPage()`, and `PerchPersistence` do not exist.

- [ ] **Step 3: Add the shared container factory and repository interface**

Create `PerchPersistence.swift`:

```swift
import SwiftData

enum PerchPersistence {
    static func makeContainer(
        storeURL: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PerchSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: PerchMigrationPlan.self,
            configurations: configuration
        )
    }
}
```

Add an async `PinnedPagePersisting: Sendable` protocol in `PageRepository.swift`. Make `PageRepository` conform. Implement `replaceCurrent(with:)` by updating/inserting the matching model, deleting every other `PinnedPageModel`, calling `beforeSave`, and saving once so replacement is atomic. Implement `currentPinnedPage()` by fetching newest-first with a fetch limit of one. Validate the stored URL with `NotionPageReference(validating:)` and ensure its page ID matches `stableID`; otherwise throw `.invalidStoredValue`.

Add `CaptureRepository.init(container:clock:beforeHelperFetch:)` and replace its duplicated model-container construction with `PerchPersistence.makeContainer(storeURL:inMemory:)`.

- [ ] **Step 4: Run focused persistence tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PageRepositoryTests
```

Expected: all `PageRepositoryTests` pass, including on-disk reopen, atomic replacement, rollback, and corruption cases.

- [ ] **Step 5: Commit the persistence boundary**

```bash
git add Sources/Perch/Persistence/PerchPersistence.swift Sources/Perch/Persistence/CaptureRepository.swift Sources/Perch/Persistence/PageRepository.swift Tests/PerchTests/PageRepositoryTests.swift
git commit -m "feat: persist the current pinned page"
```

### Task 2: Runtime restoration and ordered writes

**Files:**
- Modify: `Sources/Perch/App/AppRuntime.swift`
- Modify: `Tests/PerchTests/RuntimeActivationTests.swift`

**Interfaces:**
- Consumes: `PinnedPagePersisting.currentPinnedPage()` and `replaceCurrent(with:)`
- Produces: `AppRuntime.init(..., pageRepository: (any PinnedPagePersisting)? = nil, ...)`
- Produces: `PageActivationSource.restored`

- [ ] **Step 1: Add failing runtime tests for startup restore and persistence ordering**

Add an actor test double implementing `PinnedPagePersisting`, with continuations that can delay `currentPinnedPage()` and record `replaceCurrent(with:)` calls. Add tests that assert:

```swift
runtime.start()
await repository.waitUntilRestoreRequested()
await repository.finishRestore(with: storedPage)
await waitUntil { runtime.activePage?.pageID == firstPageID }

XCTAssertEqual(runtime.lastActivationSource, .restored)
XCTAssertTrue(panel.isVisible)
XCTAssertEqual(panel.currentPage?.pageID, firstPageID)
```

Also cover: no saved page leaves the panel hidden; a typed/direct activation while restore is delayed wins; every normal activation queues a canonical replacement; two rapid activations are saved in activation order; a thrown save leaves the panel visible; corrupt restored data leaves the runtime empty; and calling `start()` twice requests restore once.

- [ ] **Step 2: Run focused runtime tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeActivationTests
```

Expected: compilation fails because the runtime has no page repository dependency and `.restored` does not exist.

- [ ] **Step 3: Implement one-time restore and serialized writes**

Update `AppRuntime` with:

```swift
private let pageRepository: (any PinnedPagePersisting)?
private var restorePinnedPageTask: Task<Void, Never>?
private var persistPinnedPageTask: Task<Void, Never>?
```

Accept the optional repository in the initializer. In `start()`, set `started = true` before registration, register the shortcut once, and launch both existing token bootstrap and a one-time `restorePinnedPage()` task.

Refactor activation through a private method:

```swift
private func activate(
    page: NotionPageReference,
    source: PageActivationSource,
    persist: Bool
) {
    pinCoordinator.pin(page: page)
    setupOptionsPresenter?.hide()
    activePage = page
    pendingPage = page
    lastActivationSource = source

    activationGeneration &+= 1
    let generation = activationGeneration
    previewTask?.cancel()
    nativePageDocument.restoreCachedPage(pageID: page.pageID)
    previewTask = Task { [weak self] in
        await self?.loadNativePagePreview(page, generation: generation)
    }
    if persist { enqueuePersistence(of: page) }
}
```

Public activations call it with `persist: true`. Restore captures the current activation generation, awaits `currentPinnedPage()`, validates the canonical URL and matching page ID, rechecks the generation and cancellation, then calls the private activation method with `.restored` and `persist: false`.

Implement ordered writes by capturing the previous persistence task and awaiting it before calling `replaceCurrent(with:)`. Catch and log each failure so the next write still runs. Log stable page IDs and error categories only.

- [ ] **Step 4: Run focused runtime tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeActivationTests
```

Expected: all runtime activation, restore-race, ordering, failure-isolation, and idempotence tests pass.

- [ ] **Step 5: Commit runtime durability**

```bash
git add Sources/Perch/App/AppRuntime.swift Tests/PerchTests/RuntimeActivationTests.swift
git commit -m "feat: restore the pinned page at launch"
```

### Task 3: Application composition and release verification

**Files:**
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Sources/Perch/Platform/AppWindowFactory.swift`
- Test: `Tests/PerchTests/PageRepositoryTests.swift`
- Test: `Tests/PerchTests/RuntimeActivationTests.swift`

**Interfaces:**
- Consumes: `PerchPersistence.makeContainer()`, `PageRepository.init(container:)`, and `CaptureRepository.init(container:)`
- Produces: one shared persistent store for runtime page state and Quick Capture

- [ ] **Step 1: Wire one shared container at the composition root**

In `AppComposition.init()`, attempt `PerchPersistence.makeContainer()` once. On success, construct `PageRepository` and `CaptureRepository` from that container. Inject the page repository into `AppRuntime` and the capture repository into `AppWindowFactory.makeQuickCapture(repository:openInNotion:)`.

On store-open failure, log only `"Persistent store unavailable"`, pass `nil` repositories, and keep the status item, in-memory PiP activation, Settings, and the existing Quick Capture unavailable view functional.

Change `AppWindowFactory` to accept `CaptureRepository?`:

```swift
static func makeQuickCapture(
    repository: CaptureRepository?,
    openInNotion: @escaping () -> Void
) -> AppWindowPresenter {
    let content: AnyView
    if let repository {
        let session = CaptureEditorSession(repository: repository, openInNotion: openInNotion)
        content = AnyView(
            QuickCaptureView(session: session)
                .padding(DesignTokens.Spacing.container)
                .frame(minWidth: 440, minHeight: 400)
        )
    } else {
        content = AnyView(
            VStack(spacing: DesignTokens.Spacing.control) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                Text("Quick Capture is unavailable")
                    .font(.headline)
                Text("Your local draft store could not be opened. Restart the app and try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.container)
            .frame(minWidth: 360, minHeight: 220)
        )
    }
    return AppWindowPresenter(
        window: makeWindow(
            title: "Quick Capture",
            size: CGSize(width: 520, height: 520),
            content: content
        )
    )
}
```

- [ ] **Step 2: Run all automated checks**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
npm test
npm run typecheck
./script/build_and_run.sh --verify
```

Expected: all Swift tests, web tests, TypeScript checks, bundle signing, launch, and process-stability checks pass.

- [ ] **Step 3: Verify durability through a real app restart**

With `dist/Perch.app` running, activate a canonical test Notion page through the existing URL route, quit through the app menu, relaunch with `/usr/bin/open -n dist/Perch.app`, and confirm the PiP automatically opens the same canonical page. Repeat after replacing the page and confirm the replacement is restored. Do not print or record private workspace URLs in logs or the plan.

- [ ] **Step 4: Commit composition wiring**

```bash
git add Sources/Perch/App/PerchApp.swift Sources/Perch/Platform/AppWindowFactory.swift
git commit -m "feat: wire durable page restoration"
```

- [ ] **Step 5: Review the final branch diff**

Run:

```bash
git diff --check origin/master...
git status --short
git log --oneline origin/master..HEAD
```

Expected: no whitespace errors; only the pre-existing unrelated test modification remains unstaged; the branch contains the design, plan, persistence, runtime, and composition commits.
