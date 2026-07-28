# Re-pin Active Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the PiP toolbar’s clockwise-arrow control re-pin the active page by force-loading its canonical Notion URL.

**Architecture:** The toolbar sends its action through `AppComposition` into a dedicated `AppRuntime.reloadSavedPin()` command. That command intentionally bypasses persistence and delegates to a narrowly named panel and web-session recovery API, which presents the panel and creates a new `URLRequest` for the active page even when the page ID is unchanged.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, WebKit, XCTest, macOS 14.

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Keep the existing pinned-page repository unchanged; re-pinning must not enqueue a persistence write or create a new recent entry.
- Preserve normal page replacement, global shortcut, stash, and browser-opening behavior.
- Validate with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

---

### Task 1: Add force-repin behavior to the page-loading path

**Files:**
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift:65-75,196-245`
- Modify: `Sources/NotionPiP/Platform/PiPPanelCoordinator.swift:26-35,153-165`
- Test: `Tests/NotionPiPTests/NotionWebSessionTests.swift`
- Test: `Tests/NotionPiPTests/PinCoordinatorTests.swift`

**Interfaces:**
- Consumes: `NotionPageReference.canonicalURL` and `NotionPageLoading`’s existing panel lifecycle methods.
- Produces: `func reloadPinnedPage(_ page: NotionPageReference)` on `NotionPageLoading` and `PiPPanelCoordinating`; `NotionWebSession` loads a new `URLRequest` for the supplied page even when it is already active.

- [x] **Step 1: Write the failing WebSession test**

```swift
func testReloadPinnedPageForceLoadsCanonicalURLForActivePage() throws {
    var requests: [URLRequest] = []
    let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
    let page = try makePage(id: firstPageID, title: "Roadmap")

    session.activate(page: page)
    session.reloadPinnedPage(page)

    XCTAssertEqual(requests.map(\.url), [page.canonicalURL, page.canonicalURL])
    XCTAssertEqual(session.activePage, page)
    XCTAssertEqual(session.state, .loading)
}
```

- [x] **Step 2: Run the focused test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests/testReloadPinnedPageForceLoadsCanonicalURLForActivePage`

Expected: compilation failure because `reloadPinnedPage(_:)` does not exist.

- [x] **Step 3: Add the minimal WebSession API**

```swift
@MainActor
protocol NotionPageLoading: AnyObject {
    func reloadPinnedPage(_ page: NotionPageReference)
    // existing requirements
}

func reloadPinnedPage(_ page: NotionPageReference) {
    activePage = page
    revealTopControls()
    load(page.canonicalURL, pageID: page.pageID)
}
```

Add a default no-op implementation to the `NotionPageLoading` extension so existing unrelated test doubles remain focused. `NotionWebSession.reloadPinnedPage(_:)` must replace `WKWebView.reload()` with `load(page.canonicalURL, pageID: page.pageID)` so it creates a new canonical navigation even when the page ID is unchanged.

- [x] **Step 4: Add the failing panel-coordinator test and verify it fails before the coordinator implementation**

```swift
func testPanelCoordinatorReloadPinnedPageForceLoadsAndPresentsCurrentPage() throws {
    let panel = FakePanelWindow()
    let loader = FakePageLoader()
    let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
    let page = try makePage(id: firstPageID, title: "Roadmap")

    coordinator.show(page: page)
    coordinator.reloadPinnedPage(page)

    XCTAssertEqual(loader.reloadedPages, [page])
    XCTAssertEqual(panel.presentCount, 2)
    XCTAssertEqual(coordinator.currentPage, page)
}
```

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PinCoordinatorTests/testPanelCoordinatorReloadPinnedPageForceLoadsAndPresentsCurrentPage`

Expected: compilation failure until the protocol, fake, and coordinator method are present.

- [x] **Step 5: Add the minimal panel-coordinator API, then verify the focused tests pass**

Extend `PiPPanelCoordinating` with `func reloadPinnedPage(_ page: NotionPageReference)` and add a default no-op implementation for unrelated test doubles. In `PiPPanelCoordinator.reloadPinnedPage(_:)`, restore any stashed frame, dismiss the stash handle, force-load the canonical page, then present the panel and call `pageLoader.panelDidShow()`. The forced load intentionally bypasses normal hidden-session suppression so an evicted WebView receives one new navigation rather than a restore followed by a second reload.

Update `FakePageLoader` with `reloadedPages` and a `reloadPinnedPage(_:)` recorder.

- [x] **Step 6: Run the focused tests to verify the loading path passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'NotionWebSessionTests/testReloadPinnedPageForceLoadsCanonicalURLForActivePage|PinCoordinatorTests/testPanelCoordinatorReloadPinnedPageForceLoadsAndPresentsCurrentPage'`

Expected: both selected tests pass.

### Task 2: Route the toolbar action through the runtime without persistence

**Files:**
- Modify: `Sources/NotionPiP/App/PinCoordinator.swift:24-42`
- Modify: `Sources/NotionPiP/App/AppRuntime.swift:224-252`
- Modify: `Sources/NotionPiP/App/AppCommandActionRelay.swift`
- Modify: `Sources/NotionPiP/App/NotionPiPApp.swift:104-121,169-171`
- Modify: `Sources/NotionPiP/Platform/PiPPanelCoordinator.swift:38-120`
- Modify: `Sources/NotionPiP/Views/PiPChromeView.swift:40-85`
- Test: `Tests/NotionPiPTests/RuntimeActivationTests.swift`

**Interfaces:**
- Consumes: `AppRuntime.activePage`, `PinCoordinator.reloadPinnedPage(_:)`, and `PiPPanelCoordinating.reloadPinnedPage(_:)` from Task 1.
- Produces: `AppRuntime.reloadSavedPin()` and an `onReloadSavedPin` closure that the toolbar invokes; if no page is active, the runtime action is a no-op.

- [x] **Step 1: Write the failing runtime test**

```swift
func testReloadSavedPinReusesActivePageWithoutPersistingItAgain() throws {
    let panel = RuntimePanelCoordinator()
    let repository = RuntimePinnedPageRepository()
    let runtime = makeRuntime(panel: panel, pageRepository: repository)
    let page = try makePage(id: firstPageID, title: "Roadmap")
    runtime.activate(page: page, source: .typedURL)

    runtime.reloadSavedPin()

    XCTAssertEqual(panel.reloadedPages, [page])
    XCTAssertEqual(runtime.activePage, page)
}
```

Use the repository’s existing synchronization helper to assert that its saved-page write count remains the one generated by the initial activation.

- [x] **Step 2: Run the focused runtime test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeActivationTests/testReloadSavedPinReusesActivePageWithoutPersistingItAgain`

Expected: compilation failure because `reloadSavedPin()` and the fake coordinator’s `reloadedPages` are missing.

- [x] **Step 3: Add the minimal runtime and coordinator forwarding**

```swift
func reloadSavedPin() {
    guard let activePage else { return }
    pinCoordinator.reloadPinnedPage(activePage)
}
```

Add the forwarding method to `PinCoordinator`. The runtime method must not call `activate(page:source:)`, because that would enqueue another persistence write.

- [x] **Step 4: Add and test the toolbar composition callback**

Give `AppCommandActionRelay` a `reloadSavedPinAction` closure and `reloadSavedPin()` forwarding method. Pass that relay method as `PiPPanelCoordinator`’s `onReloadSavedPin` callback, then assign its closure after constructing `AppRuntime` with a weak runtime capture. Add a narrow `AppCommandActionRelayTests` case that asserts calling `reloadSavedPin()` invokes the supplied action exactly once.

- [x] **Step 5: Change the toolbar action and accessibility copy**

```swift
Button(action: onReloadSavedPin) {
    Image(systemName: "arrow.clockwise")
}
.accessibilityLabel("Re-pin current Notion page")
.help("Re-pin the current Notion page")
```

Keep the symbol and its placement unchanged. Do not route this action to `NotionWebSession.reload()`.

- [x] **Step 6: Run the focused runtime and toolbar-related tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RuntimeActivationTests/testReloadSavedPinReusesActivePageWithoutPersistingItAgain|AppCommandActionRelayTests/testReloadSavedPinInvokesConfiguredAction|NotionWebSessionTests/testPiPChromeExposesAccessibleToolbarActionsWithoutRedundantHideAction'`

Expected: all selected tests pass with the new accessibility copy.

### Task 3: Verify the complete regression suite

**Files:**
- Verify only: the files changed in Tasks 1 and 2.

**Interfaces:**
- Consumes: the complete package test suite.
- Produces: fresh verification evidence that the new re-pin action preserves all existing behavior.

- [x] **Step 1: Inspect the focused diff**

Run: `git diff -- Sources/NotionPiP/App/AppCommandActionRelay.swift Sources/NotionPiP/App/AppRuntime.swift Sources/NotionPiP/App/NotionPiPApp.swift Sources/NotionPiP/App/PinCoordinator.swift Sources/NotionPiP/Platform/NotionWebSession.swift Sources/NotionPiP/Platform/PiPPanelCoordinator.swift Sources/NotionPiP/Views/PiPChromeView.swift Tests/NotionPiPTests/NotionWebSessionTests.swift Tests/NotionPiPTests/PinCoordinatorTests.swift Tests/NotionPiPTests/RuntimeActivationTests.swift`

Expected: only the recovery route, its UI callback, updated protocol test doubles, and focused regression tests are present.

- [x] **Step 2: Run the complete Swift test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Expected: exit status 0 with all tests passing.
