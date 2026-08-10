# Persistent Corner Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible, one-click four-corner position capsule to Notion PiP while preserving the existing hover-revealed toolbar.

**Architecture:** A pure `PanelCorner` model and `PanelFramePolicy` operations calculate and detect explicit corner placement. A main-actor `PanelPositionController` binds SwiftUI intent and selected state to `PiPPanelCoordinator`, which remains the only owner of panel geometry and persistence. `PiPChromeView` renders a focused persistent capsule separately from the existing transient actions.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Core Graphics, Combine, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Preserve the retained, floating, all-Spaces `NSPanel` behavior.
- Use the current display's visible frame and the existing 24-point corner inset.
- Preserve desired content size when the effective panel frame must be reduced.
- Do not add global shortcuts, external dependencies, Node.js requirements, secrets, or signing requirements.
- Keep tests independent because Swift tests may run in parallel.
- Validate Swift changes with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## File Map

- Create `Sources/NotionPiP/Platform/PanelCorner.swift`: corner identity and anchor mapping only.
- Modify `Sources/NotionPiP/Platform/PanelFramePolicy.swift`: pure explicit-corner placement and detection.
- Create `Sources/NotionPiP/App/PanelPositionController.swift`: observable UI/controller bridge and narrow `PanelPositioning` protocol.
- Modify `Sources/NotionPiP/Platform/PiPPanelCoordinator.swift`: execute explicit moves, commit geometry, and publish selected-corner changes.
- Modify `Sources/NotionPiP/App/NotionPiPApp.swift`: create and inject the position controller.
- Create `Sources/NotionPiP/Views/PanelCornerControls.swift`: persistent four-button SwiftUI capsule.
- Modify `Sources/NotionPiP/Views/PiPChromeView.swift`: compose persistent and transient top-control layers.
- Modify `Tests/NotionPiPTests/PanelFramePolicyTests.swift`: pure placement and detection coverage.
- Create `Tests/NotionPiPTests/PanelPositionControllerTests.swift`: binding, routing, and selected-state coverage.
- Modify `Tests/NotionPiPTests/PinCoordinatorTests.swift`: retained-panel movement and geometry persistence coverage.
- Modify `Tests/NotionPiPTests/PiPChromeViewTests.swift`: stable capsule presentation and accessibility contracts.

---

### Task 1: Explicit Corner Geometry

**Files:**
- Create: `Sources/NotionPiP/Platform/PanelCorner.swift`
- Modify: `Sources/NotionPiP/Platform/PanelFramePolicy.swift`
- Test: `Tests/NotionPiPTests/PanelFramePolicyTests.swift`

**Interfaces:**
- Consumes: `PanelFrameAnchor`, `PanelFramePlacement`, `PanelFramePolicy.cornerInset`, and `PanelFramePolicy.targetVisibleFrame(for:from:)`.
- Produces: `PanelCorner`, `PanelCorner.anchor(inset:)`, `PanelFramePolicy.cornerPlacement(preferredContentSize:at:relativeTo:visibleFrames:minimumContentSize:frameForContentRect:) -> PanelFramePlacement?`, and `PanelFramePolicy.corner(for:visibleFrames:inset:tolerance:) -> PanelCorner?`.

- [ ] **Step 1: Write failing geometry tests**

Add table-driven tests that require all four placements, target-display selection, oversized fitting, nil without a display, and one-point-tolerant detection:

```swift
func testExplicitCornerPlacementSupportsEveryCorner() throws {
    let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let expected: [PanelCorner: CGRect] = [
        .topLeft: CGRect(x: 24, y: 276, width: 400, height: 500),
        .topRight: CGRect(x: 576, y: 276, width: 400, height: 500),
        .bottomLeft: CGRect(x: 24, y: 24, width: 400, height: 500),
        .bottomRight: CGRect(x: 576, y: 24, width: 400, height: 500),
    ]

    for corner in PanelCorner.allCases {
        let placement = try XCTUnwrap(
            PanelFramePolicy.cornerPlacement(
                preferredContentSize: CGSize(width: 400, height: 500),
                at: corner,
                relativeTo: CGRect(x: 300, y: 150, width: 400, height: 500),
                visibleFrames: [screen],
                minimumContentSize: .zero,
                frameForContentRect: { $0 }
            )
        )
        XCTAssertEqual(placement.frame, expected[corner])
        XCTAssertEqual(placement.anchor, corner.anchor(inset: 24))
    }
}

func testCornerDetectionAllowsOnePointFractionalTolerance() {
    let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    XCTAssertEqual(
        PanelFramePolicy.corner(
            for: CGRect(x: 24.75, y: 275.25, width: 400, height: 500),
            visibleFrames: [screen]
        ),
        .topLeft
    )
    XCTAssertNil(
        PanelFramePolicy.corner(
            for: CGRect(x: 40, y: 275, width: 400, height: 500),
            visibleFrames: [screen]
        )
    )
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelFramePolicyTests`

Expected: compilation fails because `PanelCorner`, `cornerPlacement`, and `corner(for:)` do not exist.

- [ ] **Step 3: Implement the corner model**

Create a value with stable order and an exact anchor mapping:

```swift
import CoreGraphics

enum PanelCorner: String, CaseIterable, Equatable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    func anchor(inset: CGFloat = PanelFramePolicy.cornerInset) -> PanelFrameAnchor {
        switch self {
        case .topLeft:
            PanelFrameAnchor(horizontalEdge: .left, horizontalInset: inset, verticalEdge: .top, verticalInset: inset)
        case .topRight:
            PanelFrameAnchor(horizontalEdge: .right, horizontalInset: inset, verticalEdge: .top, verticalInset: inset)
        case .bottomLeft:
            PanelFrameAnchor(horizontalEdge: .left, horizontalInset: inset, verticalEdge: .bottom, verticalInset: inset)
        case .bottomRight:
            PanelFrameAnchor(horizontalEdge: .right, horizontalInset: inset, verticalEdge: .bottom, verticalInset: inset)
        }
    }
}
```

- [ ] **Step 4: Implement placement and detection in the pure policy**

Guard that a target visible frame exists, build the requested anchor, reuse the existing `placement` function with only that target frame, and return nil if there is no display. Detect corners by comparing the live frame's four edge insets with the requested anchor using `abs(actual - expected) <= tolerance` on both axes.

```swift
static func cornerPlacement(
    preferredContentSize: CGSize,
    at corner: PanelCorner,
    relativeTo currentFrame: CGRect,
    visibleFrames: [CGRect],
    minimumContentSize: CGSize = .zero,
    frameForContentRect: (CGRect) -> CGRect
) -> PanelFramePlacement? {
    guard let visibleFrame = targetVisibleFrame(for: currentFrame, from: visibleFrames) else {
        return nil
    }
    return placement(
        preferredContentSize: preferredContentSize,
        anchoredTo: currentFrame,
        visibleFrames: [visibleFrame],
        minimumContentSize: minimumContentSize,
        preserving: corner.anchor(),
        frameForContentRect: frameForContentRect
    )
}
```

- [ ] **Step 5: Run focused tests and commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelFramePolicyTests`

Expected: PASS.

```bash
git add Sources/NotionPiP/Platform/PanelCorner.swift Sources/NotionPiP/Platform/PanelFramePolicy.swift Tests/NotionPiPTests/PanelFramePolicyTests.swift
git commit -m "Add explicit panel corner geometry"
```

---

### Task 2: Position Controller and Retained Panel Integration

**Files:**
- Create: `Sources/NotionPiP/App/PanelPositionController.swift`
- Modify: `Sources/NotionPiP/Platform/PiPPanelCoordinator.swift`
- Modify: `Sources/NotionPiP/App/NotionPiPApp.swift`
- Create: `Tests/NotionPiPTests/PanelPositionControllerTests.swift`
- Modify: `Tests/NotionPiPTests/PinCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 1's `PanelCorner` and `PanelFramePolicy.cornerPlacement`/`corner(for:)` operations.
- Produces: `PanelPositioning`, `PanelPositionController`, `PiPPanelCoordinator.movePanel(to:) -> Bool`, and `PiPPanelCoordinator.onPanelPositionChange`.

- [ ] **Step 1: Write failing controller tests**

Use a main-actor fake target and verify binding, enablement, direct action routing, and callback-driven selection clearing:

```swift
@MainActor
private final class FakePanelPositioning: PanelPositioning {
    var canPositionPanel = true
    var selectedCorner: PanelCorner? = .topRight
    var onPanelPositionChange: (@MainActor () -> Void)?
    private(set) var moves: [PanelCorner] = []

    func movePanel(to corner: PanelCorner) -> Bool {
        moves.append(corner)
        selectedCorner = corner
        onPanelPositionChange?()
        return true
    }
}

func testControllerRoutesMoveAndRefreshesSelectedCorner() {
    let target = FakePanelPositioning()
    let controller = PanelPositionController()
    controller.bind(to: target)

    XCTAssertTrue(controller.move(to: .bottomLeft))
    XCTAssertEqual(target.moves, [.bottomLeft])
    XCTAssertEqual(controller.selectedCorner, .bottomLeft)

    target.selectedCorner = nil
    target.onPanelPositionChange?()
    XCTAssertNil(controller.selectedCorner)
}
```

- [ ] **Step 2: Write failing coordinator tests**

Add tests that show a page, invoke each explicit corner, assert the animated frame call and committed geometry, and then manually move away to clear selection. Add no-page and no-display no-op tests. Extend `FakePanelWindow` to record `animate` alongside frames without changing existing assertions.

- [ ] **Step 3: Run focused tests and verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PanelPositionControllerTests|PinCoordinatorTests'`

Expected: compilation fails because the controller and coordinator positioning interfaces do not exist.

- [ ] **Step 4: Implement the controller boundary**

Create the narrow target protocol and observable controller:

```swift
@MainActor
protocol PanelPositioning: AnyObject {
    var canPositionPanel: Bool { get }
    var selectedCorner: PanelCorner? { get }
    var onPanelPositionChange: (@MainActor () -> Void)? { get set }
    @discardableResult func movePanel(to corner: PanelCorner) -> Bool
}

@MainActor
final class PanelPositionController: ObservableObject {
    @Published private(set) var selectedCorner: PanelCorner?
    @Published private(set) var canPosition = false
    private weak var target: (any PanelPositioning)?

    func bind(to target: any PanelPositioning) {
        self.target = target
        target.onPanelPositionChange = { [weak self] in self?.refresh() }
        refresh()
    }

    @discardableResult
    func move(to corner: PanelCorner) -> Bool {
        guard canPosition, target?.movePanel(to: corner) == true else { return false }
        refresh()
        return true
    }

    func refresh() {
        canPosition = target?.canPositionPanel == true
        selectedCorner = target?.selectedCorner
    }
}
```

- [ ] **Step 5: Implement coordinator positioning and state publication**

Conform `PiPPanelCoordinator` to `PanelPositioning`. Resolve desired content size from committed geometry, calculate Task 1's placement, call `setPanelFrame(..., animate: true)`, commit with the explicit anchor, and notify after explicit moves and every existing geometry-changing path. `selectedCorner` delegates to pure corner detection against the latest topology. `canPositionPanel` is `currentPage != nil`.

Update `KeyCapablePiPPanel.setFrame(_:display:animate:)` so `animate == false` or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` applies the frame immediately.

- [ ] **Step 6: Compose and bind the controller**

Create `PanelPositionController` next to `PanelSizeController` in `AppComposition`, pass it to the `PiPPanelCoordinator` convenience initializer, call `bind(to:)` after the designated initializer, and retain it for the composition lifetime.

- [ ] **Step 7: Run focused tests and commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PanelPositionControllerTests|PinCoordinatorTests'`

Expected: PASS.

```bash
git add Sources/NotionPiP/App/PanelPositionController.swift Sources/NotionPiP/App/NotionPiPApp.swift Sources/NotionPiP/Platform/PiPPanelCoordinator.swift Tests/NotionPiPTests/PanelPositionControllerTests.swift Tests/NotionPiPTests/PinCoordinatorTests.swift
git commit -m "Add retained panel positioning controls"
```

---

### Task 3: Persistent SwiftUI Corner Capsule

**Files:**
- Create: `Sources/NotionPiP/Views/PanelCornerControls.swift`
- Modify: `Sources/NotionPiP/Views/PiPChromeView.swift`
- Modify: `Sources/NotionPiP/Platform/PiPPanelCoordinator.swift`
- Test: `Tests/NotionPiPTests/PiPChromeViewTests.swift`

**Interfaces:**
- Consumes: Task 2's `PanelPositionController` with `selectedCorner`, `canPosition`, and `move(to:)`.
- Produces: `PanelCornerControls`, `PanelCorner.symbolName`, `PanelCorner.accessibilityLabel`, and a `PiPChromeView` top overlay with independently persistent leading controls.

- [ ] **Step 1: Write failing presentation-contract tests**

Assert stable order, exact symbols and labels, minimum hit target, and that persistent controls do not depend on `showsTopControls`:

```swift
func testCornerControlsExposeStableOneClickDestinations() {
    XCTAssertEqual(PanelCorner.allCases, [.topLeft, .topRight, .bottomLeft, .bottomRight])
    XCTAssertEqual(PanelCorner.topLeft.symbolName, "arrow.up.left")
    XCTAssertEqual(PanelCorner.topRight.accessibilityLabel, "Move Notion PiP to top right")
    XCTAssertEqual(PanelCornerControls.minimumHitTarget, 24)
}

func testCornerControlsRemainVisibleWithoutToolbarHover() {
    XCTAssertTrue(PiPChromeView.showsPersistentCornerControls)
    XCTAssertFalse(
        PiPChromeView.shouldShowTopControls(
            isHoveringTopEdge: false,
            isVoiceOverEnabled: false,
            isSwitchControlEnabled: false,
            isFullKeyboardAccessEnabled: false
        )
    )
}
```

- [ ] **Step 2: Run the focused view tests and verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests`

Expected: compilation fails because `PanelCornerControls` and presentation metadata do not exist.

- [ ] **Step 3: Implement the focused capsule view**

Render a plain-button `HStack(spacing: 0)` inside a compact material capsule. Give each image a 24-by-24 frame, dividers between buttons, selected semantic tint/background, `.accessibilityAddTraits(.isSelected)` for the active corner, and `.help` matching the accessibility label. Do not introduce a `Menu`, `Popover`, or second action.

- [ ] **Step 4: Refactor the PiP top overlay**

Accept `PanelPositionController? = nil`, matching the existing optional
`PanelSizeController` injection used by lightweight view tests. Production always
passes the retained controller and renders `PanelCornerControls` in a permanent
top-leading layer. Keep only the existing trailing actions under the current
opacity, offset, hit-testing, and accessibility-hidden state. Make both layers
call the same `TopControlsHoverController` so pointer movement between them
retains the toolbar.

Reserve the capsule's width in the revealed toolbar `HStack` so trailing actions never overlap it. Keep `topControlsReservedHeight` returning zero.

- [ ] **Step 5: Inject the controller into the hosted root view**

Pass the controller received by the `PiPPanelCoordinator` convenience initializer into `PiPChromeView` beside `panelSizeController`.

- [ ] **Step 6: Run focused tests and commit**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPChromeViewTests`

Expected: PASS, including all existing delayed hover behavior tests.

```bash
git add Sources/NotionPiP/Views/PanelCornerControls.swift Sources/NotionPiP/Views/PiPChromeView.swift Sources/NotionPiP/Platform/PiPPanelCoordinator.swift Tests/NotionPiPTests/PiPChromeViewTests.swift
git commit -m "Add persistent corner action capsule"
```

---

### Task 4: Integrated Validation and Manual Verification

**Files:**
- Modify only if failures reveal an in-scope regression in the files listed above.

**Interfaces:**
- Consumes: Tasks 1–3 as an integrated feature.
- Produces: a verified staged `dist/NotionPiP.app` with persistent one-click corner controls.

- [ ] **Step 1: Run the complete Swift test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Expected: all tests pass with no Swift concurrency diagnostics.

- [ ] **Step 2: Inspect the complete branch diff**

Run:

```bash
git diff --check origin/master...
git diff --stat origin/master...
git status --short
```

Confirm that no signing, entitlement, WebKit content, persistence schema, or unrelated app behavior changed.

- [ ] **Step 3: Build, stage, launch, and verify the app**

Before running the build script, check `pgrep -x NotionPiP`. If the app is active, preserve the user's work and quit it before invoking the script because the script terminates the process.

Run: `./script/build_and_run.sh --verify`

Expected: output ends with `Verified .../dist/NotionPiP.app` and a live process ID.

- [ ] **Step 4: Perform the focused manual interaction check**

Confirm the four-button capsule is visible before hover; each corner action moves in one click; current-corner selection updates; dragging away clears selection; the remaining toolbar reveals on top-edge hover without overlap or flicker; stash/restore retains the corner; and Reduce Motion applies an immediate frame change.

- [ ] **Step 5: Commit any verification-only fixes**

If Tasks 1–3 already produced a clean tree, do not create an empty commit. Otherwise stage only in-scope fixes and tests:

```bash
git add Sources/NotionPiP Tests/NotionPiPTests
git commit -m "Polish persistent corner actions"
```
