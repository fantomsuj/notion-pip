# Cursor-Adjacent Clipboard Paste Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Position the existing clipboard paste button beside the live Notion text caret while preserving its current insertion semantics and bottom-right fallback.

**Architecture:** A trusted, main-frame WebKit bridge publishes transient caret geometry to `NotionWebSession`. A pure placement policy converts CSS viewport coordinates into clamped SwiftUI coordinates, and `PiPChromeView` places the existing native button without changing clipboard or selection-token behavior.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, WebKit, XCTest, macOS 14 public APIs

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Accept caret messages only from the trusted HTTPS Notion main frame.
- Never persist caret geometry or selection geometry across a page load, web-view replacement, suspension, or process termination.
- Keep clipboard access explicit: read the general pasteboard only when the user activates the button.
- Preserve the existing `rememberCurrentEditorCursor` then `insertAtSavedEditorCursor` insertion flow.
- Do not depend on Notion private CSS classes or private DOM structure.
- Keep the button’s current help, accessibility label, prominent style, and insertion behavior.
- Preserve all unrelated worktree and branch changes.

---

## File Structure

- Create `Sources/NotionPiP/Platform/NotionEditorCaret.swift` for the caret geometry value, strict bridge parsing, handler name, and generic DOM tracking script.
- Create `Sources/NotionPiP/Platform/CursorAdjacentControlPlacement.swift` for pure CSS-to-view coordinate conversion and edge-aware placement.
- Modify `Sources/NotionPiP/Platform/NotionWebSession.swift` to install, consume, publish, and invalidate caret updates for the current web-view generation, and rename its private bridge-removal closure to cover all installed bridges.
- Modify `Sources/NotionPiP/Views/PiPChromeView.swift` to position the existing button using the placement policy.
- Create `Tests/NotionPiPTests/NotionEditorCaretTests.swift` for bridge validation.
- Create `Tests/NotionPiPTests/CursorAdjacentControlPlacementTests.swift` for placement behavior.
- Modify `Tests/NotionPiPTests/NotionWebSessionTests.swift` for lifecycle and stale-message behavior.
- Modify `Tests/NotionPiPTests/PiPChromeViewTests.swift` only for stable button constants or action-contract assertions exposed by the focused view change.
- Modify `docs/MANUAL_TEST_MATRIX.md` to record the new cursor-adjacent cases.

### Task 1: Define and validate trusted caret geometry

**Files:**
- Create: `Sources/NotionPiP/Platform/NotionEditorCaret.swift`
- Create: `Tests/NotionPiPTests/NotionEditorCaretTests.swift`

**Interfaces:**
- Produces: `NotionEditorCaretGeometry`, an `Equatable, Sendable` value containing `left`, `top`, `bottom`, `viewportWidth`, and `viewportHeight` as `Double`.
- Produces: `NotionEditorCaretUpdate`, with `.hidden` and `.visible(NotionEditorCaretGeometry)` cases.
- Produces: `NotionEditorCaretBridge.handlerName`, `.script`, and `update(from:isMainFrame:scheme:host:) -> NotionEditorCaretUpdate?`.
- Consumes: the repository’s existing trusted Notion host policy: `app.notion.com`, `notion.so`, and `www.notion.so` over HTTPS in the main frame.

- [ ] **Step 1: Write strict bridge parser tests**

  Add tests with concrete bodies:

  ```swift
  final class NotionEditorCaretTests: XCTestCase {
      func testBridgeAcceptsTrustedVisibleCaretGeometry() throws {
          let update = NotionEditorCaretBridge.update(
              from: [
                  "visible": true,
                  "left": 140.0,
                  "top": 84.0,
                  "bottom": 104.0,
                  "viewportWidth": 640.0,
                  "viewportHeight": 480.0,
              ],
              isMainFrame: true,
              scheme: "https",
              host: "app.notion.com"
          )

          XCTAssertEqual(
              update,
              .visible(NotionEditorCaretGeometry(
                  left: 140,
                  top: 84,
                  bottom: 104,
                  viewportWidth: 640,
                  viewportHeight: 480
              ))
          )
      }

      func testBridgeAcceptsTrustedHiddenUpdate() {
          XCTAssertEqual(
              NotionEditorCaretBridge.update(
                  from: ["visible": false],
                  isMainFrame: true,
                  scheme: "https",
                  host: "www.notion.so"
              ),
              .hidden
          )
      }

      func testBridgeRejectsUntrustedOrMalformedUpdates() {
          let valid: [String: Any] = [
              "visible": true,
              "left": 20.0,
              "top": 30.0,
              "bottom": 48.0,
              "viewportWidth": 500.0,
              "viewportHeight": 400.0,
          ]
          XCTAssertNil(NotionEditorCaretBridge.update(
              from: valid, isMainFrame: false, scheme: "https", host: "app.notion.com"
          ))
          XCTAssertNil(NotionEditorCaretBridge.update(
              from: valid, isMainFrame: true, scheme: "http", host: "app.notion.com"
          ))
          XCTAssertNil(NotionEditorCaretBridge.update(
              from: valid, isMainFrame: true, scheme: "https", host: "notion.example"
          ))
          XCTAssertNil(NotionEditorCaretBridge.update(
              from: valid.merging(["extra": 1]) { _, new in new },
              isMainFrame: true,
              scheme: "https",
              host: "app.notion.com"
          ))
          XCTAssertNil(NotionEditorCaretBridge.update(
              from: valid.merging(["viewportWidth": 0.0]) { _, new in new },
              isMainFrame: true,
              scheme: "https",
              host: "app.notion.com"
          ))
          XCTAssertNil(NotionEditorCaretBridge.update(
              from: valid.merging(["left": Double.infinity]) { _, new in new },
              isMainFrame: true,
              scheme: "https",
              host: "app.notion.com"
          ))
      }
  }
  ```

- [ ] **Step 2: Run the focused test and verify RED**

  Run:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionEditorCaretTests
  ```

  Expected: compilation fails because `NotionEditorCaretBridge`,
  `NotionEditorCaretUpdate`, and `NotionEditorCaretGeometry` do not exist.

- [ ] **Step 3: Implement the typed message boundary**

  Add the value and parser with exact-key validation. Use a small numeric helper
  so `NSNumber` values from `WKScriptMessage` are accepted but non-finite values
  are rejected:

  ```swift
  import Foundation

  struct NotionEditorCaretGeometry: Equatable, Sendable {
      let left: Double
      let top: Double
      let bottom: Double
      let viewportWidth: Double
      let viewportHeight: Double
  }

  enum NotionEditorCaretUpdate: Equatable, Sendable {
      case hidden
      case visible(NotionEditorCaretGeometry)
  }

  enum NotionEditorCaretBridge {
      static let handlerName = "notionPiPEditorCaret"

      static func update(
          from body: Any,
          isMainFrame: Bool,
          scheme: String,
          host: String
      ) -> NotionEditorCaretUpdate? {
          guard isMainFrame,
                scheme.lowercased() == "https",
                ["app.notion.com", "notion.so", "www.notion.so"]
                  .contains(host.lowercased()),
                let values = body as? [String: Any],
                let visible = values["visible"] as? Bool
          else { return nil }

          if !visible {
              return Set(values.keys) == Set(["visible"]) ? .hidden : nil
          }

          guard Set(values.keys) == [
              "visible", "left", "top", "bottom", "viewportWidth", "viewportHeight",
          ],
          let left = finiteDouble(values["left"]),
          let top = finiteDouble(values["top"]),
          let bottom = finiteDouble(values["bottom"]),
          let viewportWidth = finiteDouble(values["viewportWidth"]),
          let viewportHeight = finiteDouble(values["viewportHeight"]),
          viewportWidth > 0,
          viewportHeight > 0,
          bottom >= top
          else { return nil }

          return .visible(NotionEditorCaretGeometry(
              left: left,
              top: top,
              bottom: bottom,
              viewportWidth: viewportWidth,
              viewportHeight: viewportHeight
          ))
      }

      private static func finiteDouble(_ value: Any?) -> Double? {
          guard let number = value as? NSNumber else { return nil }
          let result = number.doubleValue
          return result.isFinite ? result : nil
      }
  }
  ```

- [ ] **Step 4: Add the request-animation-frame-throttled user script**

  Add `NotionEditorCaretBridge.script` in the same file. The script must:

  ```javascript
  (() => {
    if (window.__notionPiPEditorCaretInstalled) return;
    window.__notionPiPEditorCaretInstalled = true;
    let scheduled = false;
    let wasVisible = false;

    const postHidden = () => {
      if (!wasVisible) return;
      wasVisible = false;
      window.webkit?.messageHandlers?.notionPiPEditorCaret
        ?.postMessage({ visible: false });
    };

    const publish = () => {
      scheduled = false;
      const selection = window.getSelection();
      const activeElement = document.activeElement;
      if (!selection || !selection.isCollapsed || selection.rangeCount !== 1 ||
          !(activeElement instanceof Element)) {
        postHidden();
        return;
      }
      const editable = activeElement.closest('[contenteditable]');
      const anchorElement = selection.anchorNode?.nodeType === Node.ELEMENT_NODE
        ? selection.anchorNode
        : selection.anchorNode?.parentElement;
      if (!editable || !editable.isContentEditable ||
          editable.getAttribute('contenteditable') === 'false' ||
          !anchorElement || !editable.contains(anchorElement)) {
        postHidden();
        return;
      }
      const range = selection.getRangeAt(0).cloneRange();
      const rect = range.getClientRects()[0] ?? range.getBoundingClientRect();
      if (!rect || !Number.isFinite(rect.left) || !Number.isFinite(rect.top) ||
          !Number.isFinite(rect.bottom) || rect.height <= 0 ||
          rect.bottom < 0 || rect.top > window.innerHeight) {
        postHidden();
        return;
      }
      wasVisible = true;
      window.webkit?.messageHandlers?.notionPiPEditorCaret?.postMessage({
        visible: true,
        left: rect.left,
        top: rect.top,
        bottom: rect.bottom,
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
      });
    };

    const schedule = () => {
      if (scheduled) return;
      scheduled = true;
      window.requestAnimationFrame(publish);
    };

    document.addEventListener('selectionchange', schedule, true);
    document.addEventListener('input', schedule, true);
    document.addEventListener('focusin', schedule, true);
    document.addEventListener('focusout', schedule, true);
    document.addEventListener('keyup', schedule, true);
    document.addEventListener('pointerup', schedule, true);
    document.addEventListener('scroll', schedule, true);
    window.addEventListener('resize', schedule, { passive: true });
    schedule();
  })();
  ```

  Embed this as a Swift raw string. Keep it generic; do not add Notion class
  selectors, clipboard reads, selected text, or document content to messages.

- [ ] **Step 5: Run the focused test and verify GREEN**

  Run the same filtered command and require exit code 0.

- [ ] **Step 6: Commit the bridge boundary**

  ```sh
  git add Sources/NotionPiP/Platform/NotionEditorCaret.swift Tests/NotionPiPTests/NotionEditorCaretTests.swift
  git commit -m "feat: add trusted Notion caret bridge"
  ```

### Task 2: Publish only current-page caret geometry from the web session

**Files:**
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift:79-139`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift:171-217`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift:315-370`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift:586-657`
- Modify: `Sources/NotionPiP/Platform/NotionWebSession.swift:790-819`
- Modify: `Tests/NotionPiPTests/NotionWebSessionTests.swift`

**Interfaces:**
- Consumes: `NotionEditorCaretBridge.handlerName`, `.script`, and `.update(...)` from Task 1.
- Produces: `@Published private(set) var editorCaretGeometry: NotionEditorCaretGeometry?` on `NotionWebSession`.
- Produces: internal `handleEditorCaret(_:from:generation:)` routing used by tests and the weak message handler.
- Produces: private `NotionWebBridgeRemover`, renamed from `NotionWebActivityBridgeRemover` because it removes activity, scroll, and caret handlers together.
- Preserves: existing activity, scroll, selection capture/restore, web-view generation, and bridge removal behavior.

- [ ] **Step 1: Write failing session lifecycle tests**

  Add tests using the existing `makePage`, injected web views, and generation
  testing patterns in `NotionWebSessionTests`:

  ```swift
  func testCurrentWebViewCaretUpdatePublishesGeometry() throws {
      let webView = WKWebView()
      let session = NotionWebSession(webView: webView, loadRequest: { _, _ in })
      let page = try makePage(id: firstPageID, title: "Roadmap")
      session.activate(page: page)
      session.webView(webView, didFinish: nil)
      let geometry = NotionEditorCaretGeometry(
          left: 40, top: 60, bottom: 80,
          viewportWidth: 600, viewportHeight: 400
      )

      session.handleEditorCaret(.visible(geometry), from: webView)

      XCTAssertEqual(session.editorCaretGeometry, geometry)
  }

  func testRetiredWebViewCannotReplaceCurrentCaretGeometry() throws {
      let session = NotionWebSession(loadRequest: { _, _ in })
      session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
      let retired = try XCTUnwrap(session.webView)
      let stale = NotionEditorCaretGeometry(
          left: 1, top: 2, bottom: 3,
          viewportWidth: 600, viewportHeight: 400
      )

      session.webViewWebContentProcessDidTerminate(retired)
      XCTAssertFalse(session.webView === retired)

      session.handleEditorCaret(.visible(stale), from: retired)

      XCTAssertNil(session.editorCaretGeometry)
  }

  func testNavigationInvalidationClearsCaretGeometry() throws {
      let session = NotionWebSession(loadRequest: { _, _ in })
      session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
      let webView = try XCTUnwrap(session.webView)
      session.webView(webView, didFinish: nil)
      session.handleEditorCaret(.visible(.init(
          left: 40, top: 60, bottom: 80,
          viewportWidth: 600, viewportHeight: 400
      )), from: webView)

      session.webView(webView, didStartProvisionalNavigation: nil)

      XCTAssertNil(session.editorCaretGeometry)
  }
  ```

  This uses the file's existing renderer-termination route so no test-only
  replacement API is introduced. The required assertion is that a stale
  message cannot republish geometry after the retired web view is replaced.

- [ ] **Step 2: Run the focused session tests and verify RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests
  ```

  Expected: compilation fails for the missing published property and handler.

- [ ] **Step 3: Add a weak, generation-scoped caret message handler**

  Follow the existing editor-activity handler exactly:

  ```swift
  @MainActor
  private protocol NotionEditorCaretHandling: AnyObject {
      func handleEditorCaret(
          _ update: NotionEditorCaretUpdate,
          from webView: WKWebView?,
          generation: UInt
      )
  }

  @MainActor
  private final class WeakNotionEditorCaretMessageHandler: NSObject, WKScriptMessageHandler {
      weak var delegate: (any NotionEditorCaretHandling)?
      let generation: UInt

      init(generation: UInt) { self.generation = generation }

      func userContentController(
          _ userContentController: WKUserContentController,
          didReceive message: WKScriptMessage
      ) {
          guard let update = NotionEditorCaretBridge.update(
              from: message.body,
              isMainFrame: message.frameInfo.isMainFrame,
              scheme: message.frameInfo.securityOrigin.protocol,
              host: message.frameInfo.securityOrigin.host
          ) else { return }
          delegate?.handleEditorCaret(
              update,
              from: message.webView,
              generation: generation
          )
      }
  }
  ```

  Add the conformance, strong handler reference, and published geometry to
  `NotionWebSession`.

- [ ] **Step 4: Install and remove the bridge with the current web view**

  In `configure(_:)`, create the handler with the current `webViewGeneration`,
  retain it, set its delegate, and pass it to `installBridges`. In
  `installBridges`, add the Task 1 user script at `.atDocumentStart` with
  `forMainFrameOnly: true`, then add the handler in `.page` content world.

  Rename `NotionWebActivityBridgeRemover`/`removeActivityBridge` to
  `NotionWebBridgeRemover`/`removeBridges`. Extend its default closure to remove
  `NotionEditorCaretBridge.handlerName` before `removeAllUserScripts()`. In
  `retire(_:)`, nil the handler delegate and strong reference alongside the
  existing activity and scroll handlers. Update the custom remover in
  `testRendererTeardownRemovesBridgeAndObservationExactlyOnce` to remove all
  three named message handlers before removing user scripts.

- [ ] **Step 5: Publish current-generation updates and clear stale state**

  Add the routing methods:

  ```swift
  func handleEditorCaret(
      _ update: NotionEditorCaretUpdate,
      from webView: WKWebView?
  ) {
      handleEditorCaret(update, from: webView, generation: webViewGeneration)
  }

  func handleEditorCaret(
      _ update: NotionEditorCaretUpdate,
      from webView: WKWebView?,
      generation: UInt
  ) {
      guard let webView,
            isCurrent(webView, generation: generation),
            state == .active,
            loadedPageID == activePage?.pageID
      else { return }
      switch update {
      case .hidden:
          editorCaretGeometry = nil
      case let .visible(geometry):
          editorCaretGeometry = geometry
      }
  }
  ```

  Clear `editorCaretGeometry` inside `invalidateEditorSelection()`. That method
  is already called for page replacement, reload, navigation start/finish,
  failures, suspension capture, resolved SPA page changes, and renderer
  termination. Confirm retirement also reaches an invalidation path; if it does
  not in a direct test-only route, clear the property in `retire(_:)` as a final
  lifecycle backstop.

- [ ] **Step 6: Run focused session and selection tests**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionWebSessionTests
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NotionEditorSelectionTests
  ```

  Expected: both commands exit 0. The second command confirms the insertion
  snapshot behavior remains intact.

- [ ] **Step 7: Commit current-session caret publication**

  ```sh
  git add Sources/NotionPiP/Platform/NotionWebSession.swift Tests/NotionPiPTests/NotionWebSessionTests.swift
  git commit -m "feat: publish live Notion caret geometry"
  ```

### Task 3: Place the native clipboard button beside the caret

**Files:**
- Create: `Sources/NotionPiP/Platform/CursorAdjacentControlPlacement.swift`
- Create: `Tests/NotionPiPTests/CursorAdjacentControlPlacementTests.swift`
- Modify: `Sources/NotionPiP/Views/PiPChromeView.swift:1-22`
- Modify: `Sources/NotionPiP/Views/PiPChromeView.swift:213-234`
- Modify: `Tests/NotionPiPTests/PiPChromeViewTests.swift`
- Modify: `docs/MANUAL_TEST_MATRIX.md`

**Interfaces:**
- Consumes: `NotionWebSession.editorCaretGeometry` from Task 2.
- Produces: `CursorAdjacentControlPlacement.center(caret:containerSize:controlSize:) -> CGPoint`.
- Produces: `CursorAdjacentControlPlacement.fallbackCenter(containerSize:controlSize:) -> CGPoint` for the existing bottom-right behavior.
- Preserves: the exact native button action, icon, help, accessibility label, style, and control size.

- [ ] **Step 1: Write failing placement policy tests**

  Add explicit preferred, flipped, scaled, and fallback cases:

  ```swift
  import CoreGraphics
  import XCTest
  @testable import NotionPiP

  final class CursorAdjacentControlPlacementTests: XCTestCase {
      private let control = CGSize(width: 30, height: 30)

      func testPlacesControlBelowAndRightOfCaret() {
          XCTAssertEqual(
              CursorAdjacentControlPlacement.center(
                  caret: .init(
                      left: 100, top: 80, bottom: 100,
                      viewportWidth: 400, viewportHeight: 300
                  ),
                  containerSize: CGSize(width: 400, height: 300),
                  controlSize: control
              ),
              CGPoint(x: 121, y: 121)
          )
      }

      func testFlipsLeftAndAboveNearBottomRightEdge() {
          XCTAssertEqual(
              CursorAdjacentControlPlacement.center(
                  caret: .init(
                      left: 390, top: 280, bottom: 300,
                      viewportWidth: 400, viewportHeight: 300
                  ),
                  containerSize: CGSize(width: 400, height: 300),
                  controlSize: control
              ),
              CGPoint(x: 369, y: 259)
          )
      }

      func testScalesCSSViewportCoordinatesIntoViewPoints() {
          XCTAssertEqual(
              CursorAdjacentControlPlacement.center(
                  caret: .init(
                      left: 100, top: 80, bottom: 100,
                      viewportWidth: 200, viewportHeight: 150
                  ),
                  containerSize: CGSize(width: 400, height: 300),
                  controlSize: control
              ),
              CGPoint(x: 221, y: 221)
          )
      }

      func testFallbackRetainsBottomRightInset() {
          XCTAssertEqual(
              CursorAdjacentControlPlacement.fallbackCenter(
                  containerSize: CGSize(width: 400, height: 300),
                  controlSize: control
              ),
              CGPoint(x: 377, y: 277)
          )
      }
  }
  ```

  These expected points use an eight-point edge inset, six-point caret gap, and
  the center of a 30-point control.

- [ ] **Step 2: Run placement tests and verify RED**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CursorAdjacentControlPlacementTests
  ```

  Expected: compilation fails because the policy does not exist.

- [ ] **Step 3: Implement the pure placement policy**

  Implement coordinate scaling, preferred below/right origin, independent edge
  flips, clamping, and a bottom-right fallback:

  ```swift
  import CoreGraphics

  enum CursorAdjacentControlPlacement {
      static let edgeInset: CGFloat = 8
      static let caretGap: CGFloat = 6

      static func center(
          caret: NotionEditorCaretGeometry,
          containerSize: CGSize,
          controlSize: CGSize
      ) -> CGPoint {
          guard containerSize.width > 0,
                containerSize.height > 0,
                caret.viewportWidth > 0,
                caret.viewportHeight > 0
          else { return fallbackCenter(containerSize: containerSize, controlSize: controlSize) }

          let scaleX = containerSize.width / CGFloat(caret.viewportWidth)
          let scaleY = containerSize.height / CGFloat(caret.viewportHeight)
          let caretX = CGFloat(caret.left) * scaleX
          let caretTop = CGFloat(caret.top) * scaleY
          let caretBottom = CGFloat(caret.bottom) * scaleY
          var originX = caretX + caretGap
          var originY = caretBottom + caretGap

          if originX + controlSize.width > containerSize.width - edgeInset {
              originX = caretX - caretGap - controlSize.width
          }
          if originY + controlSize.height > containerSize.height - edgeInset {
              originY = caretTop - caretGap - controlSize.height
          }

          originX = min(max(originX, edgeInset),
                        max(edgeInset, containerSize.width - edgeInset - controlSize.width))
          originY = min(max(originY, edgeInset),
                        max(edgeInset, containerSize.height - edgeInset - controlSize.height))
          return CGPoint(
              x: originX + controlSize.width / 2,
              y: originY + controlSize.height / 2
          )
      }

      static func fallbackCenter(
          containerSize: CGSize,
          controlSize: CGSize
      ) -> CGPoint {
          CGPoint(
              x: max(controlSize.width / 2,
                     containerSize.width - edgeInset - controlSize.width / 2),
              y: max(controlSize.height / 2,
                     containerSize.height - edgeInset - controlSize.height / 2)
          )
      }
  }
  ```

- [ ] **Step 4: Run placement tests and verify GREEN**

  Run the filtered placement command and require exit code 0.

- [ ] **Step 5: Replace the fixed SwiftUI overlay alignment**

  Add stable constants to `PiPChromeView`:

  ```swift
  static let clipboardButtonSize = CGSize(width: 30, height: 30)
  static let clipboardButtonAccessibilityLabel = "Fill copied text at Notion cursor"
  static let clipboardButtonHelp = "Insert copied text at the current Notion cursor"
  ```

  Replace `.overlay(alignment: .bottomTrailing)` with an unaligned overlay that
  uses `GeometryReader`. Keep the button body and action unchanged:

  ```swift
  .overlay {
      GeometryReader { proxy in
          let center = webSession.editorCaretGeometry.map {
              CursorAdjacentControlPlacement.center(
                  caret: $0,
                  containerSize: proxy.size,
                  controlSize: Self.clipboardButtonSize
              )
          } ?? CursorAdjacentControlPlacement.fallbackCenter(
              containerSize: proxy.size,
              controlSize: Self.clipboardButtonSize
          )

          Button {
              let copiedText = NSPasteboard.general.string(forType: .string)
              guard let copiedText, !copiedText.isEmpty else { return }
              webSession.rememberCurrentEditorCursor { remembered in
                  guard remembered else { return }
                  webSession.insertAtSavedEditorCursor(copiedText) { _ in }
              }
          } label: {
              Label("Fill copied text", systemImage: "doc.on.clipboard")
                  .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .frame(width: Self.clipboardButtonSize.width,
                 height: Self.clipboardButtonSize.height)
          .help(Self.clipboardButtonHelp)
          .accessibilityLabel(Self.clipboardButtonAccessibilityLabel)
          .position(center)
      }
  }
  ```

  Do not add implicit animation to `editorCaretGeometry`; the button should
  track directly and stop moving when geometry stops changing.

- [ ] **Step 6: Add stable view contract assertions**

  In `PiPChromeViewTests`, assert the fixed size and accessible copy so later
  layout changes do not silently remove the deterministic placement footprint:

  ```swift
  func testClipboardButtonKeepsDeterministicAccessiblePlacementContract() {
      XCTAssertEqual(PiPChromeView.clipboardButtonSize, CGSize(width: 30, height: 30))
      XCTAssertEqual(
          PiPChromeView.clipboardButtonAccessibilityLabel,
          "Fill copied text at Notion cursor"
      )
      XCTAssertEqual(
          PiPChromeView.clipboardButtonHelp,
          "Insert copied text at the current Notion cursor"
      )
  }
  ```

- [ ] **Step 7: Run focused UI policy tests**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CursorAdjacentControlPlacementTests
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests
  ```

  Expected: both commands exit 0.

- [ ] **Step 8: Update the manual matrix**

  Add a cursor-adjacent clipboard row to `docs/MANUAL_TEST_MATRIX.md` that
  requires these observations in a signed-in Notion page:

  - collapsed caret places the button below/right;
  - right and bottom edges flip or clamp without clipping;
  - scrolling and browser zoom keep placement attached to the caret;
  - expanded selection or no active editable uses bottom-right fallback;
  - activating the button inserts clipboard text at the original caret;
  - keyboard navigation and VoiceOver expose “Fill copied text at Notion cursor”;
  - light, dark, reduced-motion, and increased-contrast appearances remain usable.

- [ ] **Step 9: Run the complete Swift validation**

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

  Expected: exit code 0 with all Swift tests passing. No Node command is needed
  because this plan does not touch `Web/QuickCaptureEditor` or generated editor
  assets.

- [ ] **Step 10: Build and manually verify the app when safe**

  First run the repository-required read-only setup checks and confirm
  `pgrep -x NotionPiP` returns no process. If the app is running, stop and ask
  the user to save work and quit it because the build script terminates the
  process. Otherwise run:

  ```sh
  ./script/build_and_run.sh --verify
  ```

  Sign in through the app UI, exercise every matrix case above, and confirm the
  script reports `Verified .../dist/NotionPiP.app` with a process ID. Never ask
  for a Notion password, session cookie, or integration token in chat or the
  terminal.

- [ ] **Step 11: Commit the cursor-adjacent control**

  ```sh
  git add Sources/NotionPiP/Platform/CursorAdjacentControlPlacement.swift \
    Sources/NotionPiP/Views/PiPChromeView.swift \
    Tests/NotionPiPTests/CursorAdjacentControlPlacementTests.swift \
    Tests/NotionPiPTests/PiPChromeViewTests.swift \
    docs/MANUAL_TEST_MATRIX.md
  git commit -m "feat: place clipboard button beside Notion caret"
  ```

## Final Verification Checklist

- [ ] `git diff origin/master...HEAD --check` reports no whitespace errors.
- [ ] `git status --short` contains only intentional work.
- [ ] Bridge tests prove origin, frame, schema, and finite-number validation.
- [ ] Session tests prove current-generation publication and stale-state clearing.
- [ ] Placement tests prove scaling, preferred placement, flips, clamping, and fallback.
- [ ] Existing selection insertion tests still pass.
- [ ] Full `swift test` exits 0 with Xcode selected through `DEVELOPER_DIR`.
- [ ] Manual verification records anything not locally testable rather than implying it passed.
