# One-Click New Notion Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an accessible `+` button to the PiP toolbar that creates a Notion page through the embedded signed-in web session and adopts the result as the current pinned page.

**Architecture:** `NotionWebSession` owns the fixed new-page navigation, duplicate-request guard, and final URL recognition. `AppCommandModel` exposes the action to the toolbar, while `AppComposition` binds resolved page URLs back into the existing `AppRuntime.activate` path so panel state, native preview, and durable pinning remain unified.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, XCTest, Swift Package Manager on macOS 14+

## Global Constraints

- Use the user's existing embedded Notion session; a personal integration token must not be required.
- The toolbar accessibility label is exactly `Create New Notion Page`.
- The toolbar help text is exactly `Create a new page in Notion`.
- The creation URL is exactly `https://www.notion.so/new`.
- Do not add title, template, parent-page, or destination UI.
- Preserve unrelated edge-stash work already present in the worktree.

---

### Task 1: Web-session creation and page recognition

**Files:**
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift`
- Test: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: Existing `NotionPageReference.init(validating:)` canonical URL validation.
- Produces: `NotionWebSession.createNewPage()`, `NotionWebSession.isCreatingNewPage: Bool`, and mutable `NotionWebSession.onPageResolved: (@MainActor (NotionPageReference) -> Void)?`.

- [x] **Step 1: Write failing creation-navigation tests**

Add tests that inject a request loader, invoke creation twice, and verify exactly one request to the fixed route:

```swift
func testCreateNewPageLoadsFixedRouteOnceUntilNavigationCompletes() throws {
    var requests: [URLRequest] = []
    let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })

    session.createNewPage()
    session.createNewPage()

    XCTAssertEqual(requests.map(\.url?.absoluteString), ["https://www.notion.so/new"])
    XCTAssertTrue(session.isCreatingNewPage)
    XCTAssertEqual(session.state, .loading)
}

func testFailedCreationAllowsAnotherAttempt() throws {
    var requests: [URLRequest] = []
    let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
    let delegate = try XCTUnwrap(session as WKNavigationDelegate)
    session.createNewPage()

    delegate.webView?(
        session.webView,
        didFailProvisionalNavigation: nil,
        withError: NSError(domain: "Test", code: 1)
    )
    session.createNewPage()

    XCTAssertEqual(requests.count, 2)
    XCTAssertTrue(session.isCreatingNewPage)
}
```

- [x] **Step 2: Run the focused tests and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests
```

Expected: compilation fails because `loadRequest`, `createNewPage`, and `isCreatingNewPage` do not exist.

- [x] **Step 3: Implement guarded new-page navigation**

Add the request loader and state to `NotionWebSession`, preserving existing defaults:

```swift
typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void

@Published private(set) var isCreatingNewPage = false
var onPageResolved: (@MainActor (NotionPageReference) -> Void)?
private let loadRequest: NotionWebRequestLoader
static let newPageURL = URL(string: "https://www.notion.so/new")!

init(
    webView: WKWebView? = nil,
    openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
    loadRequest: @escaping NotionWebRequestLoader = { webView, request in
        webView.load(request)
    }
) {
    self.webView = webView ?? Self.makeWebView()
    self.openURL = openURL
    self.loadRequest = loadRequest
    super.init()
    self.webView.navigationDelegate = self
}

func createNewPage() {
    guard !isCreatingNewPage else { return }
    isCreatingNewPage = true
    state = .loading
    loadRequest(webView, URLRequest(url: Self.newPageURL))
}
```

Route `activate(page:)` through:

```swift
loadRequest(webView, URLRequest(url: page.canonicalURL))
```

Begin both navigation-failure delegate methods with:

```swift
isCreatingNewPage = false
state = .failed(error.localizedDescription)
```

- [x] **Step 4: Add failing resolved-page adoption tests**

Add coverage for a canonical final URL and an invalid intermediate URL:

```swift
func testFinishedNavigationReportsNewCanonicalPageOnce() throws {
    var resolvedPages: [NotionPageReference] = []
    let session = NotionWebSession()
    session.onPageResolved = { resolvedPages.append($0) }
    session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
    session.webView.load(URLRequest(url: try XCTUnwrap(
        URL(string: "https://www.notion.so/New-Page-\(secondPageID)?pvs=4")
    )))
    let delegate = try XCTUnwrap(session as WKNavigationDelegate)

    delegate.webView?(session.webView, didFinish: nil)
    delegate.webView?(session.webView, didFinish: nil)

    XCTAssertEqual(resolvedPages.map(\.pageID), [secondPageID])
    XCTAssertEqual(session.activePage?.pageID, secondPageID)
    XCTAssertFalse(session.isCreatingNewPage)
}

func testFinishedIntermediateNavigationDoesNotReplaceActivePage() throws {
    var resolvedPages: [NotionPageReference] = []
    let session = NotionWebSession()
    let original = try makePage(id: firstPageID, title: "Roadmap")
    session.onPageResolved = { resolvedPages.append($0) }
    session.activate(page: original)
    session.webView.load(URLRequest(url: try XCTUnwrap(URL(string: "https://www.notion.so/new"))))
    let delegate = try XCTUnwrap(session as WKNavigationDelegate)

    delegate.webView?(session.webView, didFinish: nil)

    XCTAssertTrue(resolvedPages.isEmpty)
    XCTAssertEqual(session.activePage, original)
}
```

- [x] **Step 5: Implement final URL recognition**

At the end of `webView(_:didFinish:)`, clear the creation guard and adopt only a different valid page:

```swift
isCreatingNewPage = false
guard let url = webView.url,
      let resolvedPage = try? NotionPageReference(validating: url),
      resolvedPage.pageID != activePage?.pageID
else { return }
activePage = resolvedPage
onPageResolved?(resolvedPage)
```

This also keeps ordinary full-page Notion navigations coherent without firing a callback for the explicit activation load.

Because a direct request confirms that `https://www.notion.so/new` returns client-rendered HTML rather than an HTTP redirect, also retain an `NSKeyValueObservation` for `WKWebView.url` and call the same adoption helper from that observer. This covers Notion history changes that do not produce another navigation completion callback.

- [x] **Step 6: Run focused tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests
```

Expected: all `NotionWebSessionTests` pass.

- [x] **Step 7: Commit the web-session slice**

```bash
git add Sources/NotionPiP/Platform/NotionWebSession.swift Tests/NotionPiPTests/NotionWebSessionTests.swift
git commit -m "feat: create Notion pages in embedded session"
```

---

### Task 2: Shared command and accessible PiP toolbar button

**Files:**
- Modify: `Sources/NotionPiP/App/AppCommandModel.swift`
- Modify: `Sources/NotionPiP/Views/PiPChromeView.swift`
- Test: `Tests/NotionPiPTests/AppCommandTests.swift`
- Test: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: `NotionWebSession.createNewPage()` and `NotionWebSession.isCreatingNewPage` from Task 1.
- Produces: `AppCommandID.newNotionPage` and an icon-only toolbar control that performs it.

- [x] **Step 1: Write failing command tests**

Update the test model helper with a `newNotionPage` action and change expected groups and labels:

```swift
XCTAssertEqual(model.groups.map { $0.commands.map(\.id) }, [
    [.newNotionPage, .quickCapture],
    [.changePinnedPage],
    [.settings],
    [.quit],
])
XCTAssertEqual(model.commands.map(\.title), [
    "New Notion Page",
    "Quick Capture",
    "Change Pinned Page…",
    "Settings…",
    "Quit Notion PiP",
])
```

Construct the model with:

```swift
newNotionPage: { events(.newNotionPage) },
```

- [x] **Step 2: Run command tests and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppCommandTests
```

Expected: compilation fails because `AppCommandID.newNotionPage` and the initializer argument do not exist.

- [x] **Step 3: Add the command definition**

Add `.newNotionPage` before `.quickCapture`. Expand the no-op factory and initializer with these exact parameters:

```swift
static var noOp: AppCommandModel {
    AppCommandModel(
        newNotionPage: {},
        quickCapture: {},
        changePinnedPage: {},
        settings: {},
        quit: {}
    )
}

init(
    newNotionPage: @escaping @MainActor () -> Void,
    isNewNotionPageEnabled: @escaping @MainActor () -> Bool = { true },
    quickCapture: @escaping @MainActor () -> Void,
    changePinnedPage: @escaping @MainActor () -> Void,
    settings: @escaping @MainActor () -> Void,
    quit: @escaping @MainActor () -> Void
) {
    groups = [
        AppCommandGroup(commands: [
            AppCommand(
                id: .newNotionPage,
                title: "New Notion Page",
                isEnabled: isNewNotionPageEnabled,
                action: newNotionPage
            ),
            AppCommand(
                id: .quickCapture,
                title: "Quick Capture",
                keyEquivalent: "n",
                action: quickCapture
            ),
        ]),
        AppCommandGroup(commands: [
            AppCommand(
                id: .changePinnedPage,
                title: "Change Pinned Page…",
                action: changePinnedPage
            ),
        ]),
        AppCommandGroup(commands: [
            AppCommand(
                id: .settings,
                title: "Settings…",
                keyEquivalent: ",",
                action: settings
            ),
        ]),
        AppCommandGroup(commands: [
            AppCommand(
                id: .quit,
                title: "Quit Notion PiP",
                keyEquivalent: "q",
                action: quit
            ),
        ]),
    ]
}
```

Place this command first in the first command group:

```swift
AppCommand(
    id: .newNotionPage,
    title: "New Notion Page",
    isEnabled: isNewNotionPageEnabled,
    action: newNotionPage
),
```

Do not assign a shortcut because Command-N already belongs to Quick Capture in the current app.

- [x] **Step 4: Write the failing toolbar accessibility test**

Extend the existing PiP chrome accessibility test:

```swift
XCTAssertEqual(PiPChromeView.newPageAccessibilityLabel, "Create New Notion Page")
XCTAssertEqual(PiPChromeView.newPageHelp, "Create a new page in Notion")
```

- [x] **Step 5: Add the toolbar button**

In `PiPChromeView`, add stable copy constants and render the button immediately before Reload:

```swift
static let newPageAccessibilityLabel = "Create New Notion Page"
static let newPageHelp = "Create a new page in Notion"

Button {
    commandModel.perform(.newNotionPage)
} label: {
    Image(systemName: "plus")
}
.buttonStyle(.plain)
.disabled(!(commandModel.command(for: .newNotionPage)?.isEnabled ?? false))
.accessibilityLabel(Self.newPageAccessibilityLabel)
.help(Self.newPageHelp)
```

Keep the existing loading indicator, Reload, browser, surface, menu, stash, and hide controls unchanged.

- [x] **Step 6: Run focused command and chrome tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'AppCommandTests|NotionWebSessionTests'
```

Expected: both suites pass.

- [x] **Step 7: Commit the UI slice**

```bash
git add Sources/NotionPiP/App/AppCommandModel.swift Sources/NotionPiP/Views/PiPChromeView.swift Tests/NotionPiPTests/AppCommandTests.swift Tests/NotionPiPTests/NotionWebSessionTests.swift
git commit -m "feat: add new Notion page toolbar action"
```

---

### Task 3: Composition and unified runtime adoption

**Files:**
- Modify: `Sources/NotionPiP/App/NotionPiPApp.swift`
- Modify: `Sources/NotionPiP/App/AppRuntime.swift`
- Modify: `Sources/NotionPiP/Platform/PiPPanelCoordinator.swift`
- Test: `Tests/NotionPiPTests/RuntimeActivationTests.swift`

**Interfaces:**
- Consumes: `NotionWebSession.onPageResolved`, `NotionWebSession.createNewPage()`, `AppCommandModel(newNotionPage:...)`.
- Produces: `PageActivationSource.notionWebSession`, runtime adoption through `AppRuntime.activate(page:source:)`, and a panel initializer that accepts the composed web session.

- [x] **Step 1: Write the failing runtime source test**

Add this activation-path test:

```swift
func testEmbeddedWebSessionPageUsesUnifiedRuntimePath() throws {
    let panel = RuntimePanelCoordinator()
    let runtime = makeRuntime(panel: panel)
    let first = try makePage(id: firstPageID, title: "Roadmap")
    let created = try makePage(id: secondPageID, title: "New Page")
    runtime.activate(page: first, source: .typedURL)

    runtime.activate(page: created, source: .notionWebSession)

    XCTAssertEqual(runtime.activePage, created)
    XCTAssertEqual(runtime.lastActivationSource, .notionWebSession)
    XCTAssertEqual(panel.replacedPages, [created])
}
```

- [x] **Step 2: Run the runtime test and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RuntimeActivationTests/testEmbeddedWebSessionPageUsesUnifiedRuntimePath
```

Expected: compilation fails because `PageActivationSource.notionWebSession` does not exist.

- [x] **Step 3: Add the activation source and injectable session**

Add `case notionWebSession` to `PageActivationSource`.

Change the panel convenience initializer to accept the already-created session while preserving its default:

```swift
convenience init(
    webSession: NotionWebSession = NotionWebSession(),
    nativePageDocument: NativePageDocument = NativePageDocument(),
    commandModel: AppCommandModel = .noOp
) {
    let stashHandle = PiPStashHandleController()
    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    let defaultFrame = Self.defaultFrame(visibleFrames: visibleFrames)
    let panel = KeyCapablePiPPanel(
        contentRect: defaultFrame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )

    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.title = "Notion PiP"

    _ = panel.setFrameUsingName(Self.autosaveName)
    _ = panel.setFrameAutosaveName(Self.autosaveName)
    panel.setFrame(
        PanelFramePolicy.clamped(panel.frame, visibleFrames: visibleFrames),
        display: false
    )
    self.init(panel: panel, pageLoader: webSession, stashHandle: stashHandle)

    panel.contentView = NSHostingView(
        rootView: PiPChromeView(
            webSession: webSession,
            nativePageDocument: nativePageDocument,
            commandModel: commandModel,
            onStash: { [weak self] in
                self?.stash(visibleFrames: NSScreen.screens.map(\.visibleFrame))
            },
            onHide: { [weak self] in
                self?.hide()
            }
        )
    )
}
```

Remove the initializer's old local `let webSession = NotionWebSession()` so both the command and panel use the same session instance.

- [x] **Step 4: Wire the shared instance in `AppComposition`**

Create the web session before the command model, point the command at it, inject it into the panel, and bind page resolution after creating the runtime:

```swift
let webSession = NotionWebSession()
let commandModel = AppCommandModel(
    newNotionPage: { [weak webSession] in webSession?.createNewPage() },
    isNewNotionPageEnabled: { !webSession.isCreatingNewPage },
    quickCapture: { actionRelay.showQuickCapture() },
    changePinnedPage: { actionRelay.showSetupOptions() },
    settings: { actionRelay.showSettings() },
    quit: { actionRelay.quit() }
)
let nativePageDocument = NativePageDocument()
let panelCoordinator = PiPPanelCoordinator(
    webSession: webSession,
    nativePageDocument: nativePageDocument,
    commandModel: commandModel
)
let runtime = AppRuntime(
    panelCoordinator: panelCoordinator,
    nativePageDocument: nativePageDocument
)
webSession.onPageResolved = { [weak runtime] page in
    runtime?.activate(page: page, source: .notionWebSession)
}
```

- [x] **Step 5: Update remaining initializer call sites**

Add `newNotionPage: {}` to explicit `AppCommandModel` construction in tests and helpers. The `.noOp` model must already supply this argument internally, so views using `.noOp` require no changes.

- [x] **Step 6: Run focused integration tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RuntimeActivationTests|AppCommandTests|PinCoordinatorTests|NotionWebSessionTests'
```

Expected: all four suites pass, including existing edge-stash tests.

- [x] **Step 7: Commit the composition slice**

```bash
git add Sources/NotionPiP/App/NotionPiPApp.swift Sources/NotionPiP/App/AppRuntime.swift Sources/NotionPiP/App/AppCommandModel.swift Sources/NotionPiP/Platform/PiPPanelCoordinator.swift Tests/NotionPiPTests/AppCommandTests.swift Tests/NotionPiPTests/RuntimeActivationTests.swift
git commit -m "feat: adopt created Notion page as active pin"
```

---

### Task 4: Documentation and full verification

**Files:**
- Modify: `README.md`
- Verify: all files changed by Tasks 1–3

**Interfaces:**
- Consumes: Completed one-click creation flow.
- Produces: User-facing feature documentation and final verification evidence.

- [x] **Step 1: Document the toolbar action**

Add this section before `## Stash the PiP`:

```markdown
## Create a page from the PiP

Click the `+` button in the PiP toolbar to open a fresh page in the embedded Notion session. The new page becomes the pinned PiP page automatically; no Notion integration token is required.
```

- [x] **Step 2: Run formatting and diff checks**

Run:

```bash
git diff --check
git diff --stat origin/master...
```

Expected: no whitespace errors; the stat contains only the design, plan, feature, test, README, and pre-existing edge-stash changes.

- [x] **Step 3: Run the full Swift test suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass with zero failures.

- [x] **Step 4: Build the executable**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Expected: `Build complete!` with exit status 0.

- [x] **Step 5: Commit documentation**

```bash
git add README.md docs/superpowers/plans/2026-07-21-one-click-new-notion-page.md
git commit -m "docs: explain one-click Notion page creation"
```

- [x] **Step 6: Review final feature diff**

Run:

```bash
git diff origin/master... -- Sources/NotionPiP/App/AppCommandModel.swift Sources/NotionPiP/App/AppRuntime.swift Sources/NotionPiP/App/NotionPiPApp.swift Sources/NotionPiP/Platform/NotionWebSession.swift Sources/NotionPiP/Platform/PiPPanelCoordinator.swift Sources/NotionPiP/Views/PiPChromeView.swift Tests/NotionPiPTests/AppCommandTests.swift Tests/NotionPiPTests/NotionWebSessionTests.swift Tests/NotionPiPTests/RuntimeActivationTests.swift README.md
```

Expected: the feature matches the approved design, contains no token requirement, preserves existing controls, and has no unrelated refactor.
