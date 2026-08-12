# First Notion Page Prewarming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce cold first-page time-to-interactive by warming one hidden Notion WebView, speculatively loading a validated pasted page, and measuring a trustworthy editor-ready signal.

**Architecture:** A value-focused first-load controller decides shell warming, candidate replacement, adoption, failure, and expiry while `NotionWebSession` remains the only WebKit owner. Runtime text observation sends only validated URLs through the existing pin/panel boundaries; submission alone activates, presents, and persists. A strict document-start bridge reports a generic visible `contenteditable` surface, and privacy-safe signposts measure valid-input and submit time-to-interactive.

**Tech Stack:** Swift 6.2, macOS 14+, AppKit, SwiftUI, Combine, WebKit, OSLog signposts, XCTest.

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Keep exactly one live Notion `WKWebView`; never add a background/visible pair.
- Use `WKWebsiteDataStore.default()` and exact current `.com` plus legacy `.so` host validation.
- Do not read the clipboard speculatively; observe only app-owned URL field text.
- Do not change active page, panel presentation, history, persistence, or success UI before submission.
- Keep `WKPreferences.inactiveSchedulingPolicy = .suspend`; trace hidden progress before considering a different scheduling design.
- Expire an unused prewarm after 60 seconds and evict it immediately under memory pressure.
- Treat WebKit `didFinish` and editor-interactive as separate milestones.
- Never log URLs, page IDs, titles, workspace paths, query values, cookies, DOM content, or credentials.
- Use test-first changes and keep tests independent because Swift tests may run in parallel.
- Validate Swift changes with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

---

### Task 1: First-load prewarm state policy

**Files:**
- Create: `Sources/Perch/Platform/FirstNotionPagePrewarmController.swift`
- Create: `Tests/PerchTests/FirstNotionPagePrewarmControllerTests.swift`

**Interfaces:**
- Consumes: `NotionPageReference`.
- Produces: `FirstNotionPagePrewarmController`, `FirstNotionPagePrewarmCommand`, and `FirstNotionPageActivationDecision`.
- Produces exact methods `authorize()`, `prepare(page:)`, `navigationFinished(at:)`, `acceptsReadiness(for:)`, `markInteractive(pageID:)`, `navigationFailed(at:)`, `commit(page:)`, `expire(generation:)`, and `supersede()`.

- [ ] **Step 1: Write failing state-transition tests**

Create the test file with focused cases for authorization, canonical duplicate suppression, candidate replacement, stale URL rejection, matching adoption, failed-candidate fallback, expiry, and first-activation finality. Start with this representative adoption test:

```swift
import Foundation
import XCTest
@testable import Perch

@MainActor
final class FirstNotionPagePrewarmControllerTests: XCTestCase {
    func testMatchingInteractiveCandidateIsAdoptedWithoutAnotherLoad() throws {
        let controller = FirstNotionPagePrewarmController()
        let page = try page(id: "0123456789abcdef0123456789abcdef")

        XCTAssertEqual(controller.authorize(), .loadShell(generation: 1))
        XCTAssertEqual(
            controller.prepare(page: page),
            .loadCandidate(page: page, generation: 2)
        )
        controller.navigationFinished(at: page.canonicalURL)
        controller.markInteractive(pageID: page.pageID)

        XCTAssertEqual(
            controller.commit(page: page),
            .adoptCandidate(isInteractive: true)
        )
        XCTAssertNil(controller.prepare(page: page))
    }

    private func page(id: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.com/Page-\(id)"))
        )
    }
}
```

Also prove `acceptsReadiness(for:)` is true for a matching loading/finished
candidate and for a matching committed-but-not-yet-interactive page, then false
after `markInteractive(pageID:)`, failure, mismatch, expiry, or supersession.

Add explicit tests requiring:

```swift
XCTAssertEqual(controller.commit(page: differentPage), .loadNormally)
XCTAssertEqual(controller.commit(page: failedPage), .loadNormally)
XCTAssertFalse(controller.expire(generation: 1))
XCTAssertTrue(controller.expire(generation: 2))
XCTAssertFalse(controller.expire(generation: 2))
XCTAssertTrue(controller.supersede())
```

- [ ] **Step 2: Run the focused test and verify the missing-type failure**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter FirstNotionPagePrewarmControllerTests
```

Expected: compilation fails because the controller and command/decision types do not exist.

- [ ] **Step 3: Implement the minimal value-focused controller**

Create the controller with explicit module-internal decisions and private state:

```swift
import Foundation

enum FirstNotionPagePrewarmCommand: Equatable {
    case loadShell(generation: UInt)
    case loadCandidate(page: NotionPageReference, generation: UInt)
}

enum FirstNotionPageActivationDecision: Equatable {
    case adoptCandidate(isInteractive: Bool)
    case loadNormally
}

@MainActor
final class FirstNotionPagePrewarmController {
    private enum CandidatePhase: Equatable {
        case loading, navigationFinished, interactive, failed
    }
    private enum State: Equatable {
        case idle
        case warmingShell(generation: UInt)
        case candidate(NotionPageReference, generation: UInt, CandidatePhase)
        case committed(NotionPageReference, isInteractive: Bool)
        case superseded
        case expired
    }

    private var state: State = .idle
    private var generation: UInt = 0
    private var ownsPrewarmView = false

    func authorize() -> FirstNotionPagePrewarmCommand? {
        guard state == .idle else { return nil }
        generation &+= 1
        state = .warmingShell(generation: generation)
        ownsPrewarmView = true
        return .loadShell(generation: generation)
    }

    func prepare(page: NotionPageReference) -> FirstNotionPagePrewarmCommand? {
        switch state {
        case .committed, .superseded:
            return nil
        case .idle, .warmingShell, .candidate, .expired:
            break
        }
        if case let .candidate(existing, _, phase) = state,
           existing.canonicalURL == page.canonicalURL,
           phase != .failed { return nil }
        generation &+= 1
        state = .candidate(page, generation: generation, .loading)
        ownsPrewarmView = true
        return .loadCandidate(page: page, generation: generation)
    }

    func navigationFinished(at url: URL?) {
        guard case let .candidate(page, generation, .loading) = state,
              url == page.canonicalURL else { return }
        state = .candidate(page, generation: generation, .navigationFinished)
    }

    func markInteractive(pageID: String) {
        switch state {
        case let .candidate(page, generation, phase)
            where page.pageID == pageID && phase != .failed:
            state = .candidate(page, generation: generation, .interactive)
        case let .committed(page, false) where page.pageID == pageID:
            state = .committed(page, isInteractive: true)
        case .idle, .warmingShell, .candidate, .committed, .superseded, .expired:
            break
        }
    }

    func acceptsReadiness(for page: NotionPageReference) -> Bool {
        switch state {
        case let .candidate(candidate, _, phase):
            return candidate.pageID == page.pageID && phase != .failed
        case let .committed(committed, isInteractive):
            return committed.pageID == page.pageID && !isInteractive
        case .idle, .warmingShell, .superseded, .expired:
            return false
        }
    }

    func navigationFailed(at url: URL?) {
        guard case let .candidate(page, generation, _) = state,
              url == nil || url == page.canonicalURL else { return }
        state = .candidate(page, generation: generation, .failed)
    }

    func commit(page: NotionPageReference) -> FirstNotionPageActivationDecision {
        ownsPrewarmView = false
        guard case let .candidate(candidate, _, phase) = state,
              candidate.canonicalURL == page.canonicalURL,
              phase != .failed else {
            state = .committed(page, isInteractive: false)
            return .loadNormally
        }
        let isInteractive = phase == .interactive
        state = .committed(page, isInteractive: isInteractive)
        return .adoptCandidate(isInteractive: isInteractive)
    }

    func expire(generation expectedGeneration: UInt) -> Bool {
        guard ownsPrewarmView, generation == expectedGeneration else { return false }
        state = .expired
        ownsPrewarmView = false
        generation &+= 1
        return true
    }

    func supersede() -> Bool {
        let shouldRetire = ownsPrewarmView
        state = .superseded
        ownsPrewarmView = false
        generation &+= 1
        return shouldRetire
    }
}
```

Refine guards only as required by the complete tests; do not add WebKit, logging, timers, or persistence here.

- [ ] **Step 4: Run focused tests and confirm every policy branch passes**

Run the filtered command from Step 2. Expected: all policy tests pass.

- [ ] **Step 5: Commit the policy**

```sh
git add Sources/Perch/Platform/FirstNotionPagePrewarmController.swift \
  Tests/PerchTests/FirstNotionPagePrewarmControllerTests.swift
git commit -m "Add first page prewarm policy"
```

### Task 2: Strict editor-interactive bridge

**Files:**
- Create: `Sources/Perch/Platform/NotionEditorReadinessBridge.swift`
- Modify: `Sources/Perch/Platform/NotionWebScriptMessageCoordinator.swift`
- Create: `Tests/PerchTests/NotionEditorReadinessBridgeTests.swift`

**Interfaces:**
- Consumes: existing exact page-host validation and `WKUserContentController` lifecycle.
- Produces: `NotionEditorReadinessBridge.handlerName`, `.script`, and `.isInteractive(from:isMainFrame:scheme:host:) -> Bool`.
- Extends `NotionWebScriptMessageHandling` with `handleEditorReadiness(from:generation:)`.

- [ ] **Step 1: Write failing origin, payload, and delayed-hydration tests**

Add table-driven validation tests:

```swift
func testReadinessAcceptsOnlyStrictMainFrameNotionMessage() {
    for host in [
        "app.notion.com", "notion.com", "www.notion.com",
        "notion.so", "www.notion.so",
    ] {
        XCTAssertTrue(
            NotionEditorReadinessBridge.isInteractive(
                from: "interactive", isMainFrame: true,
                scheme: "https", host: host
            )
        )
    }
    XCTAssertFalse(
        NotionEditorReadinessBridge.isInteractive(
            from: "interactive", isMainFrame: false,
            scheme: "https", host: "www.notion.com"
        )
    )
    XCTAssertFalse(
        NotionEditorReadinessBridge.isInteractive(
            from: ["state": "interactive"], isMainFrame: true,
            scheme: "https", host: "www.notion.com"
        )
    )
}
```

Add a local `WKWebView` fixture that begins without an editable element, inserts a visible `contenteditable="true"` node after 100 ms, and verifies exactly one `interactive` message. Add fixtures for `display:none`, detached, and `contenteditable="false"` elements that never publish.

- [ ] **Step 2: Run bridge tests and verify the missing-type failure**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter NotionEditorReadinessBridgeTests
```

Expected: compilation fails because `NotionEditorReadinessBridge` is missing.

- [ ] **Step 3: Implement generic readiness detection without Notion class names**

```swift
import WebKit

enum NotionEditorReadinessBridge {
    static let handlerName = "perchEditorReadiness"

    static func isInteractive(
        from body: Any,
        isMainFrame: Bool,
        scheme: String,
        host: String
    ) -> Bool {
        isMainFrame
            && scheme.lowercased() == "https"
            && ["app.notion.com", "notion.com", "www.notion.com",
                "notion.so", "www.notion.so"].contains(host.lowercased())
            && (body as? String) == "interactive"
    }

    static let script = #"""
        (() => {
          if (window.__perchEditorReadinessInstalled) return;
          window.__perchEditorReadinessInstalled = true;
          const handler = window.webkit?.messageHandlers?.perchEditorReadiness;
          let frame = null;
          let consecutiveFrames = 0;
          let published = false;
          const visibleEditable = () => Array.from(
            document.querySelectorAll('[contenteditable]:not([contenteditable="false"])')
          ).some((element) => {
            if (!element.isConnected || !element.isContentEditable) return false;
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            return rect.width > 0 && rect.height > 0 &&
              rect.bottom > 0 && rect.right > 0 &&
              rect.top < window.innerHeight && rect.left < window.innerWidth &&
              style.display !== 'none' && style.visibility !== 'hidden';
          });
          const check = () => {
            frame = null;
            if (published) return;
            const ready = document.readyState !== 'loading' && visibleEditable();
            consecutiveFrames = ready ? consecutiveFrames + 1 : 0;
            if (consecutiveFrames >= 2) {
              published = true;
              observer.disconnect();
              handler?.postMessage('interactive');
              return;
            }
            if (ready) schedule();
          };
          const schedule = () => {
            if (frame === null && !published) frame = requestAnimationFrame(check);
          };
          const observer = new MutationObserver(schedule);
          const beginObserving = () => {
            if (!document.documentElement) {
              requestAnimationFrame(beginObserving);
              return;
            }
            observer.observe(document.documentElement, {
              childList: true, subtree: true, attributes: true,
              attributeFilter: ['contenteditable', 'style', 'hidden'],
            });
            schedule();
          };
          document.addEventListener('DOMContentLoaded', schedule, true);
          window.addEventListener('pageshow', schedule, true);
          beginObserving();
        })();
        """#
}
```

Install/remove a weak readiness handler in `NotionWebScriptMessageCoordinator` using `.atDocumentStart`, `.page`, `forMainFrameOnly: true`, and the existing activity/scroll/caret generation pattern. Include it in `removeBridges`.

- [ ] **Step 4: Run readiness and existing bridge regressions**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter 'NotionEditorReadinessBridgeTests|NotionEditorCaretBridgeTests|NotionWebSessionTests'
```

Expected: all selected tests pass with no handler lifecycle regression.

- [ ] **Step 5: Commit the readiness bridge**

```sh
git add Sources/Perch/Platform/NotionEditorReadinessBridge.swift \
  Sources/Perch/Platform/NotionWebScriptMessageCoordinator.swift \
  Tests/PerchTests/NotionEditorReadinessBridgeTests.swift
git commit -m "Detect interactive Notion editors"
```

### Task 3: First-page performance intervals

**Files:**
- Modify: `Sources/Perch/Platform/PerformanceSignposter.swift`
- Modify: `Tests/PerchTests/PerformanceSignposterTests.swift`

**Interfaces:**
- Adds `.notionFirstPageShellPrewarm`, `.notionValidInputToInteractive`, and `.notionSubmitToInteractive`.
- Adds `PerformanceOutcome.timeout`.
- Adds `PerformanceMetadata.candidateReused: Bool?` while retaining document/cache metadata.

- [ ] **Step 1: Write failing tests for repeatability, timeout, and reuse metadata**

```swift
func testFirstPageIntervalsAreRepeatableAndAcceptTimeoutMetadata() throws {
    let signposter = AppPerformanceSignposter()
    let input = try XCTUnwrap(signposter.begin(.notionValidInputToInteractive))
    let submit = try XCTUnwrap(signposter.begin(.notionSubmitToInteractive))
    signposter.end(
        input,
        outcome: .success,
        metadata: PerformanceMetadata(candidateReused: true)
    )
    signposter.end(submit, outcome: .timeout)
}
```

Also assert all three operations have `isFirstOnly == false`.

- [ ] **Step 2: Run signposter tests and verify missing enum cases fail compilation**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter PerformanceSignposterTests
```

Expected: compilation fails on the new operation/outcome/metadata cases.

- [ ] **Step 3: Add privacy-safe operation and metadata rendering**

```swift
enum PerformanceOutcome: String, Sendable {
    case success, failure, cancelled, timeout
}

struct PerformanceMetadata: Equatable, Sendable {
    var documentByteCount: Int?
    var cacheEntryCount: Int?
    var candidateReused: Bool?

    init(
        documentByteCount: Int? = nil,
        cacheEntryCount: Int? = nil,
        candidateReused: Bool? = nil
    ) {
        self.documentByteCount = documentByteCount
        self.cacheEntryCount = cacheEntryCount
        self.candidateReused = candidateReused
    }
}
```

Route the three operation cases through `webViewSignposter` and render only:

```swift
"outcome=\(outcome.rawValue, privacy: .public) candidate_reused=\(metadata.candidateReused == true, privacy: .public)"
```

Do not add arbitrary string, URL, ID, or title metadata.

- [ ] **Step 4: Run the focused tests**

Run the Step 2 command. Expected: all signposter tests pass.

- [ ] **Step 5: Commit instrumentation types**

```sh
git add Sources/Perch/Platform/PerformanceSignposter.swift \
  Tests/PerchTests/PerformanceSignposterTests.swift
git commit -m "Measure first Notion page interactivity"
```

### Task 4: One-WebView shell warming, candidate loading, and adoption

**Files:**
- Modify: `Sources/Perch/Platform/NotionWebSession.swift`
- Modify: `Sources/Perch/Platform/NotionWebScriptMessageCoordinator.swift`
- Modify: `Tests/PerchTests/NotionWebSessionTests.swift`

**Interfaces:**
- Extends `NotionPageLoading` with `prepareFirstActivation()`, `prepareFirstActivation(page:)`, and `noteFirstPageSubmission(_:)`, all with default no-op implementations.
- Consumes `FirstNotionPagePrewarmController`, `NotionEditorReadinessBridge`, and the three new performance operations.
- Adds injectable `schedulePrewarmExpiry: NotionPrewarmExpiryScheduler`.
- Produces matching-candidate adoption without a second `URLRequest`.

- [ ] **Step 1: Write failing session tests at injected WebKit seams**

Add this shell-prewarm test:

```swift
func testShellPrewarmCreatesOneWebViewAndLoadsTrustedShellWithoutActivePage() {
    var created = 0
    var requests: [URLRequest] = []
    let session = NotionWebSession(
        loadRequest: { _, request in requests.append(request) },
        webViewFactory: { created += 1; return WKWebView() },
        schedulePrewarmExpiry: { _, _ in AnyCancellable {} }
    )

    session.prepareFirstActivation()
    session.prepareFirstActivation()

    XCTAssertEqual(created, 1)
    XCTAssertEqual(requests.map(\.url?.absoluteString), ["https://app.notion.com/"])
    XCTAssertNil(session.activePage)
}
```

Add a matching-candidate test that calls `prepareFirstActivation(page:)`, then
`noteFirstPageSubmission(_:)` and `activate(page:)`, and requires exactly shell + candidate requests with no
third request. Add mismatch and failed-candidate tests that require a normal
submitted-page request. Add tests proving readiness is rejected for stale
WebView generation, shell URL, wrong page ID, and untrusted input, and accepted
for the current candidate. Add expiry/memory-pressure tests that require an
unused WebView to retire while a committed active page remains untouched.

- [ ] **Step 2: Run session tests and verify missing APIs fail compilation**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter NotionWebSessionTests
```

Expected: compilation fails on `schedulePrewarmExpiry` and preparation methods.

- [ ] **Step 3: Add bounded prewarm ownership to the session**

Add the scheduler beside the existing eviction seam:

```swift
typealias NotionPrewarmExpiryScheduler = @MainActor (
    TimeInterval,
    @escaping @MainActor () -> Void
) -> AnyCancellable
```

Append these requirements to the existing `NotionPageLoading` declaration:

```swift
func prepareFirstActivation()
func prepareFirstActivation(page: NotionPageReference)
func noteFirstPageSubmission(_ page: NotionPageReference)
```

Add these defaults to the existing extension so unrelated doubles compile:

```swift
extension NotionPageLoading {
    func prepareFirstActivation() {}
    func prepareFirstActivation(page: NotionPageReference) {}
    func noteFirstPageSubmission(_ page: NotionPageReference) {}
}
```

Inject its default implementation using a cancellable `Task`, exactly like
`scheduleEviction`. Add controller, expiry cancellable, readiness timeout task,
and interval-token properties. Use 60 seconds for expiry and 30 seconds for
readiness timeout.

```swift
private let firstPagePrewarm = FirstNotionPagePrewarmController()
private let schedulePrewarmExpiry: NotionPrewarmExpiryScheduler
private var prewarmExpiry: AnyCancellable?
private var readinessTimeoutTask: Task<Void, Never>?
private var shellPrewarmToken: PerformanceIntervalToken?
private var validInputToInteractiveToken: PerformanceIntervalToken?
private var submitToInteractiveToken: PerformanceIntervalToken?
private var firstPageSubmittedPageID: String?
private var firstPageCandidateWasReused = false
```

Implement `noteFirstPageSubmission(_:)` to start
`.notionSubmitToInteractive` only once for the submitted page. Store its page ID
so unrelated restore/page-picker activations cannot end the interval. If the
candidate was already interactive, `activate(page:)` ends this token
immediately after committing the matching candidate.

```swift
func noteFirstPageSubmission(_ page: NotionPageReference) {
    guard firstPageSubmittedPageID == nil else { return }
    firstPageSubmittedPageID = page.pageID
    submitToInteractiveToken = performanceSignposter?.begin(
        .notionSubmitToInteractive
    )
    scheduleReadinessTimeoutIfNeeded()
}
```

Implement shell and candidate preparation without the normal `load` helper,
because speculative loads must not record durable restoration state:

```swift
func prepareFirstActivation() {
    guard case let .loadShell(generation) = firstPagePrewarm.authorize(),
          let shellURL = URL(string: "https://app.notion.com/") else { return }
    shellPrewarmToken = performanceSignposter?.begin(.notionFirstPageShellPrewarm)
    loadRequest(ensureWebView(), URLRequest(url: shellURL))
    prewarmExpiry = schedulePrewarmExpiry(60) { [weak self] in
        self?.expireFirstPagePrewarm(expectedGeneration: generation)
    }
}

func prepareFirstActivation(page: NotionPageReference) {
    guard case let .loadCandidate(_, generation) = firstPagePrewarm.prepare(page: page)
    else { return }
    prewarmExpiry?.cancel()
    prewarmExpiry = schedulePrewarmExpiry(60) { [weak self] in
        self?.expireFirstPagePrewarm(expectedGeneration: generation)
    }
    beginValidInputMeasurement()
    loadRequest(ensureWebView(), URLRequest(url: page.canonicalURL))
}
```

The expiration helper calls `firstPagePrewarm.expire(generation:)` and retires
the WebView only when it returns `true`; it never reaches into controller state.

```swift
private func expireFirstPagePrewarm(expectedGeneration: UInt) {
    guard firstPagePrewarm.expire(generation: expectedGeneration) else { return }
    prewarmExpiry?.cancel()
    prewarmExpiry = nil
    readinessTimeoutTask?.cancel()
    finishShellPrewarm(outcome: .cancelled)
    finishInteractiveMeasurements(outcome: .cancelled)
    if let webView { _ = retire(webView) }
}
```

- [ ] **Step 4: Adopt matching candidates in normal activation**

In `activate(page:restoration:)`, call `firstPagePrewarm.commit(page:)` before
page-switch teardown. For `.adoptCandidate`, set `activePage`, `loadedPageID`,
restoration preparation, and lifecycle state without issuing a request. Use
`.active` only when `isInteractive` is true; otherwise use `.loading`. For
`.loadNormally`, preserve `restoreOrLoad` and reuse the already warmed WebView
for the submitted canonical request.

Set `firstPageCandidateWasReused = true` only in `.adoptCandidate`; set it to
`false` in `.loadNormally`. If adoption reports `isInteractive == true`, call
`finishInteractiveMeasurements(candidateReused: true)` after state is
committed so a submit that follows already-completed speculation ends
immediately.

While prewarm is uncommitted, navigation callbacks update only prewarm phase
and signposts. They must not publish a user-visible failure, resolve an active
page, capture restoration, show caret controls, or call `onPageResolved`.
Candidate failure marks the policy failed so submission retries normally.
End shell prewarm with `.success` when its navigation finishes, `.failure` for
its noncancellation failure, and `.cancelled` when candidate navigation,
expiry, supersession, retirement, or renderer termination replaces it.

Implement strict readiness handling:

```swift
func handleEditorReadiness(from webView: WKWebView?, generation: UInt) {
    guard let webView,
          isCurrent(webView, generation: generation),
          let url = webView.url,
          let page = try? NotionPageReference(validating: url),
          firstPagePrewarm.acceptsReadiness(for: page)
    else { return }
    firstPagePrewarm.markInteractive(pageID: page.pageID)
    finishInteractiveMeasurements(
        candidateReused: firstPageCandidateWasReused
    )
}
```

Add `acceptsReadiness(for:)` to Task 1's controller and test it there. End every
token on success, cancellation, failure, timeout, expiry, retirement, and
renderer termination. A readiness signal received before submission is stored;
the submit interval then begins and ends immediately when the candidate is
committed.

Add concrete helpers so no interval remains dangling:

```swift
private func finishShellPrewarm(outcome: PerformanceOutcome) {
    performanceSignposter?.end(shellPrewarmToken, outcome: outcome)
    shellPrewarmToken = nil
}

private func beginValidInputMeasurement() {
    performanceSignposter?.end(
        validInputToInteractiveToken,
        outcome: .cancelled
    )
    validInputToInteractiveToken = performanceSignposter?.begin(
        .notionValidInputToInteractive
    )
    scheduleReadinessTimeoutIfNeeded()
}

private func scheduleReadinessTimeoutIfNeeded() {
    readinessTimeoutTask?.cancel()
    guard validInputToInteractiveToken != nil || submitToInteractiveToken != nil
    else { return }
    readinessTimeoutTask = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        self?.finishInteractiveMeasurements(outcome: .timeout)
    }
}

private func finishInteractiveMeasurements(
    outcome: PerformanceOutcome = .success,
    candidateReused: Bool? = nil
) {
    readinessTimeoutTask?.cancel()
    readinessTimeoutTask = nil
    let metadata = PerformanceMetadata(candidateReused: candidateReused)
    performanceSignposter?.end(
        validInputToInteractiveToken,
        outcome: outcome,
        metadata: metadata
    )
    performanceSignposter?.end(
        submitToInteractiveToken,
        outcome: outcome,
        metadata: metadata
    )
    validInputToInteractiveToken = nil
    submitToInteractiveToken = nil
}
```

- [ ] **Step 5: Run session, lifecycle, navigation, and popup regressions**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter 'NotionWebSessionTests|NotionWebLifecycleControllerTests|WebNavigationDestinationTests|NotionWebPopupCoordinatorTests'
```

Expected: selected suites pass with one WebView, no duplicate candidate load,
and unchanged login/navigation behavior.

- [ ] **Step 6: Commit WebKit integration**

```sh
git add Sources/Perch/Platform/NotionWebSession.swift \
  Sources/Perch/Platform/NotionWebScriptMessageCoordinator.swift \
  Tests/PerchTests/NotionWebSessionTests.swift
git commit -m "Prewarm the first Notion web session"
```

### Task 5: Runtime URL speculation and panel forwarding

**Files:**
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`
- Modify: `Sources/Perch/App/PinCoordinator.swift`
- Modify: `Sources/Perch/App/AppRuntime.swift`
- Modify: `Sources/Perch/App/AppRuntime+Persistence.swift`
- Modify: `Sources/Perch/App/AppRuntime+Activation.swift`
- Modify: `Sources/Perch/App/PerchApp.swift`
- Modify: `Tests/PerchTests/PinCoordinatorTests.swift`
- Modify: `Tests/PerchTests/PageURLInputPresenterTests.swift`
- Modify: `Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift`
- Modify: `Tests/PerchTests/AppRuntimeTestSupport.swift`

**Interfaces:**
- Extends `PiPPanelCoordinating` with `prepareFirstActivation()` and `prepareFirstActivation(page:)`, defaulting to no-op for unrelated test doubles.
- Extends `PiPPanelCoordinating` and `PinCoordinator` with `noteFirstPageSubmission(_:)` forwarding.
- Adds `firstPageSpeculationDelay: Duration = .milliseconds(75)` and `firstPagePrewarmingEnabled: Bool = true` to `AppRuntime.init`.
- Adds developer-only launch argument `--disable-first-page-prewarm` for Release A/B measurement; it is not a user preference.

- [ ] **Step 1: Write failing forwarding and runtime observation tests**

Add a panel test requiring forwarding without presentation:

```swift
func testPanelForwardsFirstActivationPreparationWithoutPresenting() throws {
    let panel = FakePanelWindow()
    let loader = FakePageLoader()
    let coordinator = PiPPanelCoordinator(panel: panel, pageLoader: loader)
    let page = try makePage(id: firstPageID, title: "Roadmap")

    coordinator.prepareFirstActivation()
    coordinator.prepareFirstActivation(page: page)

    XCTAssertEqual(loader.prepareShellCount, 1)
    XCTAssertEqual(loader.preparedPages, [page])
    XCTAssertEqual(panel.presentCount, 0)
    XCTAssertNil(coordinator.currentPage)
}
```

Add runtime tests with `.zero` speculation delay proving:

- empty restore calls shell prewarm once;
- valid `.com` and legacy `.so` text prepares the canonical page;
- invalid text, canonical duplicates, and active-page edits do not prepare;
- preparation changes no active/pending page, panel visibility, persistence,
  validation UI, or input visibility;
- immediate submission may beat speculation and still activates normally;
- restored and external pages cancel pending speculation.
- `firstPagePrewarmingEnabled: false` produces no shell or candidate preparation.
- typed submission forwards one submission note immediately before activation;
  restored, external, and page-picker activation forward none.

- [ ] **Step 2: Run affected tests and verify missing forwarding APIs fail**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter 'PinCoordinatorTests|PageURLInputPresenterTests|RuntimePinnedPagePersistenceTests'
```

Expected: compilation fails on preparation methods and initializer delay.

- [ ] **Step 3: Implement no-presentation forwarding**

Append these requirements to `PiPPanelCoordinating`:

```swift
func prepareFirstActivation()
func prepareFirstActivation(page: NotionPageReference)
func noteFirstPageSubmission(_ page: NotionPageReference)
```

Add protocol defaults and production forwarding:

```swift
extension PiPPanelCoordinating {
    func prepareFirstActivation() {}
    func prepareFirstActivation(page: NotionPageReference) {}
    func noteFirstPageSubmission(_ page: NotionPageReference) {}
}

// PiPPanelCoordinator
func prepareFirstActivation() { pageLoader.prepareFirstActivation() }
func prepareFirstActivation(page: NotionPageReference) {
    pageLoader.prepareFirstActivation(page: page)
}
func noteFirstPageSubmission(_ page: NotionPageReference) {
    pageLoader.noteFirstPageSubmission(page)
}
```

Forward all three methods through `PinCoordinator` without accessing the pasteboard.

- [ ] **Step 4: Observe validated input with a cancellable coalescing task**

Retain `pageURLInputObservation: AnyCancellable?`,
`pageURLPrewarmTask: Task<Void, Never>?`, the enabled flag, and the injected delay. Observe `$text`
after all stored properties are initialized:

```swift
pageURLInputObservation = inputState.$text.sink { [weak self] text in
    self?.scheduleFirstPageSpeculation(from: text)
}

private func scheduleFirstPageSpeculation(from text: String) {
    pageURLPrewarmTask?.cancel()
    guard firstPagePrewarmingEnabled, activePage == nil else { return }
    let delay = firstPageSpeculationDelay
    pageURLPrewarmTask = Task { [weak self] in
        do { try await Task.sleep(for: delay) } catch { return }
        guard let self, self.activePage == nil,
              case let .success(page) = pinCoordinator.page(from: text),
              pageURLInputState.text == text else { return }
        pinCoordinator.prepareFirstActivation(page: page)
    }
}
```

After empty restoration resolves and before presenting Settings or first-page
input, call this idempotent helper:

```swift
func prepareFirstActivationIfEmpty() {
    guard firstPagePrewarmingEnabled, activePage == nil else { return }
    pinCoordinator.prepareFirstActivation()
}
```

In `PerchApp`, pass the developer-only switch explicitly:

```swift
let prewarmingEnabled = !ProcessInfo.processInfo.arguments.contains(
    "--disable-first-page-prewarm"
)
let runtime = AppRuntime(firstPagePrewarmingEnabled: prewarmingEnabled)
```

Cancel `pageURLPrewarmTask` at the start of every actual activation; do not wait
for it. Submission continues through current validation/activation so the
WebSession alone decides adoption.

In `validatePageURL()`, call
`pinCoordinator.noteFirstPageSubmission(page)` immediately before
`activate(page:source: .typedURL)`. Do not call it from the generic private
activation method because restored, external, and page-picker sources are not
URL-field submissions.

- [ ] **Step 5: Run runtime, panel, and activation tests**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter 'PinCoordinatorTests|PageURLInputPresenterTests|RuntimePinnedPagePersistenceTests|RuntimeActivationAndMenuBarTests'
```

Expected: all selected tests pass with no presentation or persistence before
submission.

- [ ] **Step 6: Commit runtime integration**

```sh
git add Sources/Perch/Platform/PiPPanelCoordinator.swift \
  Sources/Perch/App/PinCoordinator.swift \
  Sources/Perch/App/AppRuntime.swift \
  Sources/Perch/App/AppRuntime+Persistence.swift \
  Sources/Perch/App/AppRuntime+Activation.swift \
  Sources/Perch/App/PerchApp.swift \
  Tests/PerchTests/PinCoordinatorTests.swift \
  Tests/PerchTests/PageURLInputPresenterTests.swift \
  Tests/PerchTests/RuntimePinnedPagePersistenceTests.swift \
  Tests/PerchTests/AppRuntimeTestSupport.swift
git commit -m "Speculate the first pasted Notion page"
```

### Task 6: Baseline guide, regression pass, and real-page gate

**Files:**
- Create: `docs/FIRST_PAGE_PERFORMANCE_BASELINE.md`
- Modify: `docs/MANUAL_TEST_MATRIX.md`
- Review: all files changed by Tasks 1–5.

**Interfaces:**
- Consumes the three signpost operations and readiness signal.
- Produces a reproducible privacy-safe A/B procedure; raw traces and private page data stay out of git.

- [ ] **Step 1: Write the baseline guide**

Create the guide with this content and expand only the Instruments launch
instructions:

```markdown
# First Notion Page Performance Baseline

Use a Release build, one Mac, one network, one signed-in account, and one
editable test page. Never record its URL, title, workspace path, content,
cookies, or credentials.

Run ten alternating baseline and prewarm launches, using
`open -n dist/Perch.app --args --disable-first-page-prewarm` for baseline
and `open -n dist/Perch.app` for prewarm. Quit between runs; do not
clear WebKit website data because persistent cache is normal product behavior.
Record only milliseconds, candidate reuse, timeout/success, peak memory, and
qualitative energy impact.

| Run | Variant | Valid input → interactive (ms) | Submit → interactive (ms) | Candidate reused | Peak memory (MB) | Outcome |
|---:|---|---:|---:|---|---:|---|

Accept when median valid-input → interactive improves by at least 20%, median
native cold launch regresses by no more than 10%, matching adoption issues no
duplicate request, and no panel/persistence occurs before submit.
```

Document Time Profiler, Hangs, Allocations, Memory, and an os_signpost track
filtered to subsystem `com.fantomsuj.Perch`. State raw traces are local
diagnostic artifacts and must not be committed.

- [ ] **Step 2: Extend the manual matrix**

Add rows for signed-in cold load, signed-out login, editable empty/populated
pages, read-only/no-permission pages, `.com`, legacy `.so`, offline, slow
network, immediate/delayed submit, changed URL, 60-second expiry, memory
pressure, and termination during prewarm. Each row states expected panel and
persistence behavior and whether editor-interactive is expected.

- [ ] **Step 3: Run the full test suite**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 4: Inspect the complete diff**

```sh
git diff --check
git status --short
git diff origin/master... -- Sources/Perch Tests/PerchTests \
  docs/FIRST_PAGE_PERFORMANCE_BASELINE.md docs/MANUAL_TEST_MATRIX.md
```

Confirm one live WebView, exact origins, no private metadata or clipboard
monitoring, no pre-submit persistence/presentation, bounded expiry, and token
completion on every terminal path.

- [ ] **Step 5: Stage safely and verify**

First run `pgrep -x Perch`. If a process is running and ownership is not
clearly from this test session, stop and ask the user to save work and quit;
the build script terminates `Perch`. Otherwise run:

```sh
./script/build_and_run.sh --verify
```

Expected: `Verified .../dist/Perch.app` with a live PID.

- [ ] **Step 6: Execute the real-page A/B gate without automating credentials**

Follow `docs/FIRST_PAGE_PERFORMANCE_BASELINE.md`. Record only a sanitized table
in the implementation handoff. If hidden navigation does not progress while
the retained panel is ordered out, report that measured blocker and stop; do
not change `.suspend` or add an offscreen-window workaround in this change.

- [ ] **Step 7: Commit verification documentation**

```sh
git add docs/FIRST_PAGE_PERFORMANCE_BASELINE.md docs/MANUAL_TEST_MATRIX.md
git commit -m "Document first page performance validation"
```
