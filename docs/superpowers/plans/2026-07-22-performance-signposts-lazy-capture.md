# Performance Signposts and Lazy Quick Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure the app's cold launch and first window presentations, then remove Quick Capture's unused-at-launch `WKWebView` cost without changing capture behavior.

**Architecture:** Add a small typed `OSSignposter` adapter with opaque interval tokens so feature code never logs user content or depends directly on `OSSignpostIntervalState`. Inject the adapter at the existing AppKit presentation seams. Then add a generic lazy presenter that defers the existing Quick Capture factory as one unit and keeps the created window/session warm after first use.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, WebKit, OSLog, XCTest, SwiftPM on macOS 14+

## Global Constraints

- Use the subsystem `com.fantomsuj.Perch` and categories prefixed with `performance.`.
- Signposts must never include URLs, page IDs or titles, draft IDs or contents, integration tokens, request IDs, or error descriptions.
- `ColdLaunchToStatusItem`, `FirstPiPPresentation`, and `FirstQuickCapturePresentation` are first-only intervals; duplicate begins return no token and emit no second interval.
- Quick Capture must not construct `AppWindowPresenter`, `NSWindow`, `NSHostingView`, `CaptureEditorSession`, or `WKWebView` before the first `show()`.
- After first use, Quick Capture remains warm and is reused; timed eviction and memory-pressure teardown are out of scope until the editor exposes an acknowledged autosave-flush contract.
- Preserve all existing Quick Capture autosave, exact retry, conflict, stash/restore, relaunch, focus, and accessibility behavior.
- Run Swift commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

### Task 1: Typed performance signposts for launch and first presentations

**Files:**
- Create: `Sources/Perch/Platform/PerformanceSignposter.swift`
- Create: `Tests/PerchTests/PerformanceSignposterTests.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Sources/Perch/App/AppDelegate.swift`
- Modify: `Sources/Perch/Platform/AppWindowPresenter.swift`
- Modify: `Sources/Perch/Platform/AppWindowFactory.swift`
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Modify: `Tests/PerchTests/AppWindowPresenterTests.swift`
- Modify: `Tests/PerchTests/PinCoordinatorTests.swift`

**Interfaces:**
- Produces: `PerformanceOperation`, `PerformanceOutcome`, opaque `PerformanceIntervalToken`, `PerformanceSignposting`, and `AppPerformanceSignposter.shared`.
- Produces: injectable first-presentation measurement in `AppWindowPresenter` and `PiPPanelCoordinator`.
- Consumes: existing `AppWindow`, `PiPPanelWindow`, and `AppDelegate` lifecycle seams.

- [ ] **Step 1: Add failing tests for first-only intervals and presentation boundaries**

Add a spy conforming to this exact protocol and tests which assert one balanced begin/end pair despite two presentations:

```swift
@MainActor
protocol PerformanceSignposting: AnyObject {
    @discardableResult
    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken?
    func end(_ token: PerformanceIntervalToken?, outcome: PerformanceOutcome)
}
```

The `AppWindowPresenterTests` case must call `show()` twice and require one `.firstQuickCapturePresentation` begin/end pair while the fake window is presented twice. The `PinCoordinatorTests` case must present, hide, and re-present a page and require one `.firstPiPPresentation` begin/end pair. `PerformanceSignposterTests` must require the production recorder's first begin to return a token, the duplicate begin to return `nil`, and repeated/`nil` ends to be safe.

- [ ] **Step 2: Verify the focused tests fail because the telemetry API and injections do not exist**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceSignposterTests|AppWindowPresenterTests|PinCoordinatorTests'
```

Expected: compilation fails for missing `PerformanceSignposting`/performance-aware initializers or the new first-only assertions fail.

- [ ] **Step 3: Implement the typed signposter**

Define these stable cases:

```swift
enum PerformanceOperation: String, CaseIterable, Sendable {
    case coldLaunchToStatusItem = "ColdLaunchToStatusItem"
    case firstPiPPresentation = "FirstPiPPresentation"
    case firstQuickCapturePresentation = "FirstQuickCapturePresentation"
}

enum PerformanceOutcome: String, Sendable {
    case success
    case failure
    case cancelled
}

struct PerformanceIntervalToken: Hashable, Sendable {
    fileprivate let id: UUID
}
```

`AppPerformanceSignposter` must own category-specific `OSSignposter` values for `performance.lifecycle` and `performance.presentation`, map every operation through an exhaustive switch to a static signpost name, store active `OSSignpostIntervalState` values behind the opaque token, suppress duplicate begins for all three first-only operations, and make `end(nil, ...)` and repeated ends no-ops. End messages may include only `outcome=<public enum raw value>`.

- [ ] **Step 4: Instrument the exact lifecycle boundaries**

Begin `ColdLaunchToStatusItem` at the first line of `PerchApp.init`, bind its token to `AppDelegate` through `AppStartup.start`, and end it with `.success` in `applicationDidFinishLaunching` after composition has already constructed/configured `StatusItemController`.

Add optional injected `performanceSignposter` and `firstPresentationOperation` parameters to `AppWindowPresenter`; wrap only the first `window.presentAsKey()` call. Configure the Quick Capture presenter with `.firstQuickCapturePresentation` in `AppWindowFactory`.

Add an optional injected `performanceSignposter` to `PiPPanelCoordinator`; begin before first page activation/presentation and end after `panel.present()` for whichever path (`show`, `showCurrentPage`, or stash restore) presents first. Subsequent presentations must remain unmeasured.

- [ ] **Step 5: Run focused and full Swift verification**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PerformanceSignposterTests|AppWindowPresenterTests|PinCoordinatorTests'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: focused tests pass and the full suite reports 0 failures.

- [ ] **Step 6: Commit Task 1**

```sh
git add Sources/Perch/Platform/PerformanceSignposter.swift Sources/Perch/App/PerchApp.swift Sources/Perch/App/AppDelegate.swift Sources/Perch/Platform/AppWindowPresenter.swift Sources/Perch/Platform/AppWindowFactory.swift Sources/Perch/Platform/PiPPanelCoordinator.swift Tests/PerchTests/PerformanceSignposterTests.swift Tests/PerchTests/AppWindowPresenterTests.swift Tests/PerchTests/PinCoordinatorTests.swift .gitignore docs/superpowers/plans/2026-07-22-performance-signposts-lazy-capture.md
git commit -m "feat: instrument launch and first presentations"
```

---

### Task 2: Defer Quick Capture construction until first presentation

**Files:**
- Modify: `Sources/Perch/Platform/AppWindowPresenter.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Sources/Perch/Platform/AppWindowFactory.swift`
- Modify: `Tests/PerchTests/AppWindowPresenterTests.swift`

**Interfaces:**
- Consumes: `AppWindowPresenting`, `PerformanceSignposting`, and `.firstQuickCapturePresentation` from Task 1.
- Produces: `LazyAppWindowPresenter`, initialized with `makePresenter: @escaping @MainActor () -> any AppWindowPresenting` and optional first-presentation telemetry.

- [ ] **Step 1: Add failing lazy-construction tests**

Add tests which use a factory counter and fake presenter/window to prove:

```swift
let presenter = LazyAppWindowPresenter {
    factoryCount += 1
    return AppWindowPresenter(window: window)
}
```

- initialization leaves `factoryCount == 0`;
- `hide()` before `show()` leaves `factoryCount == 0`;
- first `show()` changes `factoryCount` to `1` and presents once;
- second `show()` keeps `factoryCount == 1` and presents twice;
- `hide()` after construction forwards once;
- `.firstQuickCapturePresentation` begins before the factory runs and ends after the created presenter has shown, so the interval includes window, hosting view, editor session, and `WKWebView` construction.

- [ ] **Step 2: Verify the tests fail for the missing lazy presenter**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppWindowPresenterTests
```

Expected: compilation fails because `LazyAppWindowPresenter` does not exist.

- [ ] **Step 3: Implement the minimal lazy presenter**

Implement the shape below, with first-presentation measurement around both creation and the first forwarded `show()`:

```swift
@MainActor
final class LazyAppWindowPresenter: AppWindowPresenting {
    private let makePresenter: @MainActor () -> any AppWindowPresenting
    private var presenter: (any AppWindowPresenting)?

    init(makePresenter: @escaping @MainActor () -> any AppWindowPresenting) {
        self.makePresenter = makePresenter
    }

    func show() {
        let presenter = presenter ?? makeAndCachePresenter()
        presenter.show()
    }

    func hide() {
        presenter?.hide()
    }
}
```

Do not add eviction timers, close callbacks, bridge teardown, or capture-session changes in this task.

- [ ] **Step 4: Route Quick Capture through the lazy wrapper**

In `AppComposition`, retain the wrapper strongly as `any AppWindowPresenting`, assign the same wrapper to `AppCommandActionRelay`, and weakly capture it from setup options. Put the existing `AppWindowFactory.makeQuickCapture(repository:openInNotion:)` call wholly inside `makePresenter` so none of its window/editor work runs during composition.

Move `.firstQuickCapturePresentation` telemetry from the concrete `AppWindowPresenter` factory configuration to `LazyAppWindowPresenter`, ensuring the interval still exists exactly once and now includes lazy construction.

- [ ] **Step 5: Run focused, full, and packaged-app verification**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppWindowPresenterTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
npm test
npm run typecheck
./script/build_and_run.sh --verify
```

Expected: 0 failures, 0 type errors, and the packaged accessory app remains running through the verification interval.

- [ ] **Step 6: Commit Task 2**

```sh
git add Sources/Perch/Platform/AppWindowPresenter.swift Sources/Perch/App/PerchApp.swift Sources/Perch/Platform/AppWindowFactory.swift Tests/PerchTests/AppWindowPresenterTests.swift
git commit -m "perf: lazy-load quick capture"
```

---

## Deferred follow-up

After collecting launch/presentation traces, add `CaptureAutosave`, `NativePreviewFetch`, and view-commit `NativePreviewRender` intervals. Treat Quick Capture eviction as a separate design task requiring an async JavaScript flush acknowledgement, cancellation/generation tokens, termination integration, and proof that closing during the 300 ms debounce cannot lose work.
