# Draggable Edge Stash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the stashed Perch edge tab draggable across displays and snap it to the nearest horizontal edge on release without restoring or reloading the live page.

**Architecture:** Extend the pure stash geometry policy with drag-end snapping, add a testable AppKit pointer interaction surface to the existing SwiftUI handle, and let the panel coordinator retain placement changes for the current stash session. The main PiP panel and WebView remain untouched while the handle moves.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, XCTest, macOS 14+

## Global Constraints

- Keep `Command-Shift-P` and menu-bar behavior unchanged.
- Preserve the hidden panel frame, current page, WebView instance, navigation state, and session while moving the handle.
- The handle remains 36 by 96 points, joins all Spaces, and stays within `NSScreen.visibleFrame` after snapping.
- Placement lasts only for the current stash session and is not persisted.
- Do not add dependencies.

---

### Task 1: Drag-end placement policy

**Files:**
- Modify: `Tests/PerchTests/PanelStashPolicyTests.swift`
- Modify: `Sources/Perch/Platform/PanelStashPolicy.swift`

**Interfaces:**
- Consumes: `PanelFramePolicy.targetVisibleFrame(for:from:)` and `PanelStashPolicy.handleSize`.
- Produces: `PanelStashPolicy.snappedPlacement(for:visibleFrames:) -> PanelStashPlacement?`.

- [ ] **Step 1: Write failing policy tests**

Add tests that call the not-yet-defined API with a dragged handle on the opposite side, near the top visible boundary, across two displays, and with no display:

```swift
let placement = try XCTUnwrap(
    PanelStashPolicy.snappedPlacement(
        for: CGRect(x: 120, y: 210, width: 36, height: 96),
        visibleFrames: [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
    )
)
XCTAssertEqual(placement, PanelStashPlacement(side: .left, frame: CGRect(x: 0, y: 210, width: 36, height: 96)))
```

- [ ] **Step 2: Verify the tests fail for the missing API**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelStashPolicyTests`

Expected: compile failure reporting that `PanelStashPolicy` has no member `snappedPlacement`.

- [ ] **Step 3: Implement minimal snapping geometry**

Add:

```swift
static func snappedPlacement(
    for handleFrame: CGRect,
    visibleFrames: [CGRect]
) -> PanelStashPlacement? {
    guard let visibleFrame = PanelFramePolicy.targetVisibleFrame(
        for: handleFrame,
        from: visibleFrames
    ) else { return nil }

    let side: PanelStashSide = handleFrame.midX <= visibleFrame.midX ? .left : .right
    let x = side == .left ? visibleFrame.minX : visibleFrame.maxX - handleSize.width
    let y = min(max(handleFrame.minY, visibleFrame.minY), visibleFrame.maxY - handleSize.height)
    return PanelStashPlacement(
        side: side,
        frame: CGRect(origin: CGPoint(x: x, y: y), size: handleSize)
    )
}
```

- [ ] **Step 4: Verify policy tests pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelStashPolicyTests`

Expected: all `PanelStashPolicyTests` pass.

- [ ] **Step 5: Commit the geometry slice**

```bash
git add Sources/Perch/Platform/PanelStashPolicy.swift Tests/PerchTests/PanelStashPolicyTests.swift
git commit -m "feat: snap dragged stash handle to screen edge"
```

### Task 2: Click-versus-drag AppKit interaction

**Files:**
- Create: `Tests/PerchTests/PiPStashHandleInteractionTests.swift`
- Modify: `Sources/Perch/Views/PiPStashHandleView.swift`

**Interfaces:**
- Consumes: the handle panel supplied by `NSView.window`.
- Produces: internal `PiPStashHandleInteractionView`, initialized with `onActivate` and `onDragEnded`, and `PiPStashHandleView(side:onRestore:onDragEnded:)`.

- [ ] **Step 1: Write failing interaction tests**

Create tests with an `NSPanel`, an injectable pointer-location closure, and synthetic mouse events. Verify a one-point move calls activation without moving the panel; verify a forty-point move changes the panel origin, calls drag completion once, and never calls activation.

```swift
var pointer = CGPoint(x: 10, y: 10)
let interaction = PiPStashHandleInteractionView(
    pointerLocation: { pointer },
    onActivate: { activations += 1 },
    onDragEnded: { completedFrames.append($0) }
)
window.contentView = interaction
interaction.mouseDown(with: mouseEvent(.leftMouseDown))
pointer = CGPoint(x: 50, y: 70)
interaction.mouseDragged(with: mouseEvent(.leftMouseDragged))
interaction.mouseUp(with: mouseEvent(.leftMouseUp))
XCTAssertEqual(window.frame.origin, CGPoint(x: 140, y: 160))
XCTAssertEqual(activations, 0)
XCTAssertEqual(completedFrames, [window.frame])
```

- [ ] **Step 2: Verify the tests fail for the missing interaction view**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPStashHandleInteractionTests`

Expected: compile failure reporting that `PiPStashHandleInteractionView` is not in scope.

- [ ] **Step 3: Implement the AppKit interaction surface**

Add an internal `NSView` subclass that records pointer and panel origin on mouse-down, crosses a 3-point Euclidean threshold in `mouseDragged`, moves the panel with `setFrameOrigin`, and chooses `onActivate` versus `onDragEnded` in `mouseUp`. Give the view button accessibility role, label, hint, press action, and the tooltip `Drag to move; click to restore Perch`.

Add a private `NSViewRepresentable` wrapper and replace the SwiftUI `Button` with a `ZStack`: the existing material/symbol visuals are accessibility-hidden beneath the interaction surface.

- [ ] **Step 4: Verify interaction tests pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PiPStashHandleInteractionTests`

Expected: click and drag tests pass with no failures.

- [ ] **Step 5: Commit the interaction slice**

```bash
git add Sources/Perch/Views/PiPStashHandleView.swift Tests/PerchTests/PiPStashHandleInteractionTests.swift
git commit -m "feat: drag the stashed PiP handle"
```

### Task 3: Snap controller and retain placement

**Files:**
- Modify: `Tests/PerchTests/PinCoordinatorTests.swift`
- Modify: `Sources/Perch/Platform/PiPStashHandleController.swift`
- Modify: `Sources/Perch/Platform/PiPPanelCoordinator.swift`

**Interfaces:**
- Consumes: `PanelStashPolicy.snappedPlacement(for:visibleFrames:)` and the interaction view's final dragged frame.
- Produces: `PiPStashHandle.present(placement:onRestore:onPlacementChange:)` and current-session placement retention inside `PiPPanelCoordinator`.

- [ ] **Step 1: Write failing coordinator tests**

Extend `FakeStashHandle` to capture the placement callback and expose `move(to:)`. Add tests proving a moved left-side placement is the source for a later screen reconfiguration and a restore followed by a new stash uses the main panel's placement rather than the prior drag.

```swift
handle.move(to: PanelStashPlacement(side: .left, frame: CGRect(x: 0, y: 100, width: 36, height: 96)))
coordinator.reclampPanelFrame(visibleFrames: [CGRect(x: 0, y: 0, width: 1_200, height: 900)])
XCTAssertEqual(handle.placements.last, PanelStashPlacement(side: .left, frame: CGRect(x: 0, y: 100, width: 36, height: 96)))
```

- [ ] **Step 2: Verify coordinator tests fail against the old protocol**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PinCoordinatorTests`

Expected: compile failure because `present` has no placement-change callback and the fake has no `move(to:)`.

- [ ] **Step 3: Implement snapping in the handle controller**

Inject a visible-frame provider into `PiPStashHandleController`. Pass `onDragEnded` into `PiPStashHandleView`; when called, compute a snapped placement, restore the last valid frame if no display resolves, otherwise apply the snapped frame, rebuild the side-dependent content, and invoke `onPlacementChange`.

- [ ] **Step 4: Retain current-session placement in the coordinator**

Extend `PiPStashHandle.present` with `onPlacementChange`. Store `activeStashPlacement` when stashing, update it from the callback, use its frame as the source for screen-change snapping, and clear it whenever the handle is dismissed by restore, hide, show, or replace.

- [ ] **Step 5: Verify coordinator and interaction tests pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PinCoordinatorTests|PiPStashHandleInteractionTests|PanelStashPolicyTests'`

Expected: all focused tests pass.

- [ ] **Step 6: Commit the orchestration slice**

```bash
git add Sources/Perch/Platform/PiPStashHandleController.swift Sources/Perch/Platform/PiPPanelCoordinator.swift Tests/PerchTests/PinCoordinatorTests.swift
git commit -m "feat: retain dragged stash placement"
```

### Task 4: Documentation and full verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: completed drag behavior.
- Produces: user-facing usage documentation and verification evidence.

- [ ] **Step 1: Document the gesture**

Update the stash section to state that the edge tab can be dragged to either side or a different height and snaps to the nearest horizontal edge on release.

- [ ] **Step 2: Run the complete verification suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
npm test
npm run typecheck
./script/build_and_run.sh --verify
git diff --check
```

Expected: all Swift tests pass, all 27 web tests pass, TypeScript exits zero, app verification exits zero, and `git diff --check` prints nothing.

- [ ] **Step 3: Commit docs and any verification-only fixes**

```bash
git add README.md
git commit -m "docs: explain draggable stash handle"
```

- [ ] **Step 4: Review scope**

Run: `git diff origin/master...HEAD --stat && git status --short`

Expected: only the draggable-stash design, plan, implementation, tests, and README are changed; the worktree is clean.
