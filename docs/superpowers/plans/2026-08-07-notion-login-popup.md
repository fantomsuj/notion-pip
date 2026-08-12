# Notion Login Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the embedded Notion page while completing Google, Apple, or SAML login in a temporary in-app WebKit popup, and stop HTTPS subframes from opening blank browser tabs.

**Architecture:** Make the navigation policy frame-aware so main-frame, subframe, and new-window requests have distinct decisions. Add a main-actor popup coordinator that owns one temporary AppKit window and a child `WKWebView` created from WebKit's supplied configuration, then wire it into `NotionWebSession` without changing the main WebView's ownership.

**Tech Stack:** Swift 6.2, AppKit, WebKit, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve Swift 6.2, macOS 14, the public API, signing, and entitlements.
- Keep `WKWebsiteDataStore.default()` and never copy, log, or expose cookies or credentials.
- Keep exact top-level trusted-host checks; only existing HTTP(S) subframes receive broader internal handling.
- Use structured main-actor ownership without `@unchecked Sendable`, `nonisolated(unsafe)`, or detached tasks.
- Keep tests independent because the Swift suite may run in parallel.
- Do not alter product behavior outside WebKit navigation and login-popup lifecycle.

---

### Task 1: Make Navigation Decisions Frame-Aware

**Files:**
- Modify: `Sources/Perch/Platform/NotionWebNavigationPolicy.swift`
- Modify: `Sources/Perch/Platform/NotionWebSession.swift`
- Test: `Tests/PerchTests/NotionWebNavigationPolicyTests.swift`
- Test: `Tests/PerchTests/WebNavigationDestinationTests.swift`

**Interfaces:**
- Produces: `NotionWebNavigationContext` with `.mainFrame`, `.subframe`, and `.newWindow`.
- Produces: `NotionWebNavigationPolicy.actionDecision(for:context:)`.
- Produces: `NotionWebNewWindowDecision.createPopup` for an initial trusted Notion request.
- Preserves: top-level external HTTP(S) URLs open through the injected `openURL` closure exactly once.

- [ ] **Step 1: Write failing frame-policy regression tests**

Add literal behavior tests that fail if a subframe is promoted to a browser action or a trusted popup is collapsed into the main view:

```swift
func testAllowsExternalHTTPSSubframeWithoutOpeningBrowser() throws {
    var openedURLs: [URL] = []
    let session = NotionWebSession(openURL: { openedURLs.append($0) })
    let analyticsURL = try XCTUnwrap(
        URL(string: "https://aif.notion.so/aif-production.html")
    )

    XCTAssertEqual(
        session.navigationPolicy(for: analyticsURL, context: .subframe),
        .allow
    )
    XCTAssertTrue(openedURLs.isEmpty)
}

func testExternalMainFrameStillOpensBrowserOnce() throws {
    var openedURLs: [URL] = []
    let session = NotionWebSession(openURL: { openedURLs.append($0) })
    let externalURL = try XCTUnwrap(URL(string: "https://example.com/path"))

    XCTAssertEqual(
        session.navigationPolicy(for: externalURL, context: .mainFrame),
        .cancel
    )
    XCTAssertEqual(openedURLs, [externalURL])
}

func testTrustedNewWindowProducesPopupDecision() throws {
    let policy = NotionWebNavigationPolicy()
    let request = URLRequest(
        url: try XCTUnwrap(
            URL(string: "https://app.notion.com/verifyNoPopupBlockerHtmlAndRedirect")
        )
    )

    XCTAssertEqual(policy.newWindowDecision(for: request), .createPopup)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter WebNavigationDestinationTests
```

Expected: compilation/test failures because `NotionWebNavigationContext`, the `context:` API, and `.createPopup` do not exist.

- [ ] **Step 3: Implement the minimal frame-aware policy**

Replace the boolean target-frame input with the explicit context and keep new-window side effects deferred to `WKUIDelegate`:

```swift
enum NotionWebNavigationContext: Equatable {
    case mainFrame
    case subframe
    case newWindow
}

enum NotionWebNewWindowDecision: Equatable {
    case createPopup
    case openExternally(URL)
    case ignore
}

func actionDecision(
    for url: URL?,
    context: NotionWebNavigationContext
) -> NotionWebNavigationActionDecision {
    guard context != .newWindow else { return .allow }

    switch WebNavigationDestination.classify(url) {
    case .trustedNotion:
        return .allow
    case .externalWeb where context == .subframe:
        return .allow
    case .externalWeb:
        guard let url else { return .cancel }
        return .openExternally(url)
    case .unsupported:
        return .cancel
    }
}
```

Map `WKNavigationAction.targetFrame == nil` to `.newWindow`, `isMainFrame == true` to `.mainFrame`, and every other existing frame to `.subframe` in `NotionWebSession`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same filtered command. Expected: all `WebNavigationDestinationTests` pass with no unexpected browser-open side effects.

- [ ] **Step 5: Commit the frame-policy change**

```sh
git add Sources/Perch/Platform/NotionWebNavigationPolicy.swift \
  Sources/Perch/Platform/NotionWebSession.swift \
  Tests/PerchTests/NotionWebNavigationPolicyTests.swift \
  Tests/PerchTests/WebNavigationDestinationTests.swift
git commit -m "Fix Notion subframe navigation routing"
```

---

### Task 2: Add the Temporary WebKit Popup Coordinator

**Files:**
- Create: `Sources/Perch/Platform/NotionWebPopupCoordinator.swift`
- Create: `Tests/PerchTests/NotionWebPopupCoordinatorTests.swift`

**Interfaces:**
- Consumes: `WebNavigationDestination.classify(_:)` for supported HTTP(S) popup navigation.
- Produces: `NotionWebPopupCoordinating.present(using:) -> WKWebView` and `close()`.
- Produces: a default `NotionWebPopupCoordinator` that owns one child WebView and one temporary AppKit window.
- Produces: `NotionWebPopupWindowing`, a narrow production boundary implemented by the default window and deterministic test doubles.

- [ ] **Step 1: Write failing popup ownership tests**

Create tests that name the regressions: discarding WebKit's supplied configuration, failing to detach a closed popup, or allowing unsupported schemes.

```swift
@MainActor
func testPresentUsesSuppliedConfigurationAndPresentsDistinctWebView() {
    let expectedConfiguration = WKWebViewConfiguration()
    let window = PopupWindowSpy()
    var receivedConfiguration: WKWebViewConfiguration?
    let coordinator = NotionWebPopupCoordinator(
        makeWebView: { configuration in
            receivedConfiguration = configuration
            return WKWebView(frame: .zero, configuration: configuration)
        },
        makeWindow: { window }
    )

    let popup = coordinator.present(using: expectedConfiguration)

    XCTAssertTrue(receivedConfiguration === expectedConfiguration)
    XCTAssertTrue(window.presentedWebView === popup)
    XCTAssertTrue(popup.navigationDelegate === coordinator)
    XCTAssertTrue(popup.uiDelegate === coordinator)
}

@MainActor
func testWindowCloseDetachesPopupDelegates() {
    let window = PopupWindowSpy()
    let coordinator = NotionWebPopupCoordinator(makeWindow: { window })
    let popup = coordinator.present(using: WKWebViewConfiguration())

    window.simulateUserClose()

    XCTAssertNil(popup.navigationDelegate)
    XCTAssertNil(popup.uiDelegate)
}

@MainActor
func testPopupAllowsHTTPSIdentityProviderAndRejectsUnsupportedScheme() throws {
    let coordinator = NotionWebPopupCoordinator()

    XCTAssertEqual(
        coordinator.navigationPolicy(
            for: try XCTUnwrap(URL(string: "https://accounts.google.com/signin"))
        ),
        .allow
    )
    XCTAssertEqual(
        coordinator.navigationPolicy(
            for: try XCTUnwrap(URL(string: "file:///tmp/credentials"))
        ),
        .cancel
    )
}
```

The test-only `PopupWindowSpy` implements the complete window boundary: it records the presented WebView, counts `close()`, stores the production close callback, and exposes `simulateUserClose()` only from the test file.

- [ ] **Step 2: Run the popup tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter NotionWebPopupCoordinatorTests
```

Expected: compilation failure because the coordinator and window boundary do not exist.

- [ ] **Step 3: Implement the minimal coordinator and default window**

Create these production contracts and ownership behavior:

```swift
@MainActor
protocol NotionWebPopupCoordinating: AnyObject {
    func present(using configuration: WKWebViewConfiguration) -> WKWebView
    func close()
}

@MainActor
protocol NotionWebPopupWindowing: AnyObject {
    var onClose: (@MainActor () -> Void)? { get set }
    func present(webView: WKWebView)
    func close()
}

@MainActor
final class NotionWebPopupCoordinator: NSObject, NotionWebPopupCoordinating {
    private struct Popup {
        let window: any NotionWebPopupWindowing
        let webView: WKWebView
    }

    private var popup: Popup?

    func present(using configuration: WKWebViewConfiguration) -> WKWebView {
        close()
        let webView = makeWebView(configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let window = makeWindow()
        window.onClose = { [weak self] in self?.detachCurrentPopup() }
        popup = Popup(window: window, webView: webView)
        window.present(webView: webView)
        return webView
    }

    func close() {
        guard let popup else { return }
        self.popup = nil
        popup.window.onClose = nil
        detach(popup.webView)
        popup.window.close()
    }
}
```

The concrete window uses a `640 x 720` content rect, `.titled`, `.closable`, `.resizable`, and `.miniaturizable` style masks, title `Sign in to Notion`, `isReleasedWhenClosed = false`, and `makeKeyAndOrderFront(nil)`. The coordinator allows `.trustedNotion` and `.externalWeb` popup navigations, cancels `.unsupported`, closes on `webViewDidClose`, loads nested trusted Notion windows in the same popup, and opens nested external windows through the injected `openURL` closure.

- [ ] **Step 4: Run popup tests and verify GREEN**

Run the same filtered popup test command. Expected: all popup lifecycle and navigation tests pass.

- [ ] **Step 5: Commit the popup coordinator**

```sh
git add Sources/Perch/Platform/NotionWebPopupCoordinator.swift \
  Tests/PerchTests/NotionWebPopupCoordinatorTests.swift
git commit -m "Add in-app Notion login popup"
```

---

### Task 3: Wire Popup Ownership into the Main Notion Session

**Files:**
- Modify: `Sources/Perch/Platform/NotionWebSession.swift`
- Modify: `Tests/PerchTests/WebNavigationDestinationTests.swift`
- Modify: `Tests/PerchTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: `NotionWebNavigationPolicy.newWindowDecision(for:)` and `NotionWebPopupCoordinating`.
- Preserves: `NotionWebSession` remains the sole owner/delegate of the main WebView.
- Guarantees: trusted new-window callbacks return a child WebView and never call the injected main `loadRequest` closure.
- Guarantees: retiring or recovering the main WebView closes the active popup.

- [ ] **Step 1: Write failing session integration tests**

Replace the old same-WebView expectation with a child-popup expectation:

```swift
@MainActor
func testTrustedNewWindowReturnsPopupWithoutReplacingMainWebView() throws {
    let mainWebView = WKWebView()
    let popupWebView = WKWebView()
    let popupCoordinator = PopupCoordinatorSpy(webView: popupWebView)
    var mainLoads: [URLRequest] = []
    let session = NotionWebSession(
        webView: mainWebView,
        loadRequest: { _, request in mainLoads.append(request) },
        popupCoordinator: popupCoordinator
    )
    let configuration = WKWebViewConfiguration()
    let request = URLRequest(
        url: try XCTUnwrap(
            URL(string: "https://app.notion.com/verifyNoPopupBlockerHtmlAndRedirect")
        )
    )

    let returned = session.handleNewWindowRequest(
        request,
        configuration: configuration,
        in: mainWebView
    )

    XCTAssertTrue(returned === popupWebView)
    XCTAssertTrue(popupCoordinator.receivedConfiguration === configuration)
    XCTAssertTrue(mainLoads.isEmpty)
    XCTAssertTrue(session.webView === mainWebView)
}
```

Add a lifecycle test using the spy that activates a different valid page or triggers renderer recovery and asserts `closeCallCount == 1`. Keep the spy complete but narrow: `present(using:)`, `close()`, returned WebView, received configuration, and close count.

- [ ] **Step 2: Run session tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter 'WebNavigationDestinationTests|NotionWebSessionTests'
```

Expected: compilation/test failure because `NotionWebSession` does not accept a popup coordinator or configuration in its handler and still loads trusted popup requests into the main view.

- [ ] **Step 3: Implement minimal session wiring**

Inject an optional coordinator and default it using the existing `openURL` closure:

```swift
private let popupCoordinator: any NotionWebPopupCoordinating

// Insert immediately after the existing loadRequest parameter.
popupCoordinator: (any NotionWebPopupCoordinating)? = nil,

// Assign with the other stored dependencies before super.init().
self.popupCoordinator = popupCoordinator
    ?? NotionWebPopupCoordinator(openURL: openURL)
```

Change the UI delegate and test seam to pass WebKit's exact configuration:

```swift
func handleNewWindowRequest(
    _ request: URLRequest,
    configuration: WKWebViewConfiguration,
    in webView: WKWebView
) -> WKWebView? {
    guard isCurrent(webView) else { return nil }
    switch navigationDecisionPolicy.newWindowDecision(for: request) {
    case .createPopup:
        return popupCoordinator.present(using: configuration)
    case let .openExternally(url):
        openURL(url)
        return nil
    case .ignore:
        return nil
    }
}
```

Call `popupCoordinator.close()` from main-WebView retirement and renderer termination before changing or rebuilding the opener session.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same combined filtered command. Expected: all frame policy, popup integration, and main-session lifecycle tests pass.

- [ ] **Step 5: Run the complete Swift suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass without warnings or parallel-test interference.

- [ ] **Step 6: Build, launch, and verify the real app**

Run:

```sh
./script/build_and_run.sh --verify
```

Expected: the command prints `Verified .../dist/Perch.app` with a live PID. Paste the existing clipboard Notion URL, trigger Google sign-in, and verify that the main panel remains on Notion, a titled in-app sign-in window appears, and no `aif.notion.so` browser tab opens. Do not enter or request user credentials.

- [ ] **Step 7: Commit the session integration**

```sh
git add Sources/Perch/Platform/NotionWebSession.swift \
  Tests/PerchTests/WebNavigationDestinationTests.swift \
  Tests/PerchTests/NotionWebSessionTests.swift
git commit -m "Preserve Notion page during login popups"
```

- [ ] **Step 8: Review the branch diff and prepare the draft PR**

Run:

```sh
git diff --check
git status --short
git diff --stat origin/master...
git log --oneline origin/master..HEAD
```

Expected: no whitespace errors, no uncommitted changes, and only the design, plan, popup implementation, navigation policy, and regression tests differ from `origin/master`.
