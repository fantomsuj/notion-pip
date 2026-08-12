# Display Topology Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Keep one retained Perch panel and at most one stash handle reachable through deterministic multi-display topology changes without reloading the live Notion page.

**Architecture:** Add pure display descriptors, affinity selection, stash intent, and revision-gated topology decisions. A small AppKit observer produces snapshots; PiPPanelCoordinator reconciles its existing panel or handle without mutating committed geometry during automatic fallback.

**Tech Stack:** Swift 6.2, AppKit, Core Graphics, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Preserve the intentional all-Spaces floating NSPanel and stash-handle roles.
- Do not redesign built-in or custom panel sizes.
- Do not recreate the panel, handle, WKWebView, or Notion session for a screen change.
- Do not require Node.js, secrets, Notion credentials, or signing certificates.

---

## File Map

- Create Sources/Perch/Domain/DisplayTopology.swift for pure topology and affinity.
- Create Sources/Perch/Platform/PanelTopologyPolicy.swift for pure presentation decisions.
- Create Sources/Perch/Platform/AppKitDisplayTopologyObserver.swift for NSScreen observation.
- Modify PanelGeometry, PanelGeometryPolicy, PanelStashPolicy, and PiPPanelCoordinator.
- Add synthetic policy tests and coordinator regressions.
- Expand docs/MANUAL_TEST_MATRIX.md.

### Task 1: Pure Display Topology And Affinity

**Files:**
- Create: Sources/Perch/Domain/DisplayTopology.swift
- Create: Tests/PerchTests/DisplayTopologyPolicyTests.swift

**Interfaces:**
- Produces DisplayDescriptor, DisplayAffinity, DisplayTopology, and DisplayTopologyPolicy.targetDisplay.
- Consumes Core Graphics frames in AppKit point coordinates.

- [ ] **Step 1: Write failing synthetic topology tests**

Cover exact identifier matching after left/right rearrangement, strong replacement matching after identifier and scale changes, primary fallback while the intended display is absent, and deterministic ties. Fixtures use:

~~~swift
let primary = DisplayDescriptor(
    identifier: 1,
    frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
    visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
    backingScaleFactor: 2,
    isPrimary: true
)
let topology = DisplayTopology(revision: 1, displays: [primary])
~~~

- [ ] **Step 2: Run the focused tests and verify they fail**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DisplayTopologyPolicyTests
~~~

Expected: compilation fails because the topology types do not exist.

- [ ] **Step 3: Implement the pure values and selector**

~~~swift
struct DisplayDescriptor: Codable, Equatable, Sendable {
    let identifier: UInt32?
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
    let isPrimary: Bool
}

struct DisplayAffinity: Codable, Equatable, Sendable {
    enum Placement: String, Codable, Equatable, Sendable {
        case primary, left, right, above, below
    }
    let identifier: UInt32?
    let visibleSize: CGSize
    let backingScaleFactor: CGFloat
    let isPrimary: Bool
    let placement: Placement
}

struct DisplayTopology: Equatable, Sendable {
    let revision: UInt64
    let displays: [DisplayDescriptor]
}

enum DisplayTopologyPolicy {
    static func affinity(
        for display: DisplayDescriptor,
        in topology: DisplayTopology
    ) -> DisplayAffinity

    static func targetDisplay(
        for affinity: DisplayAffinity?,
        currentFrame: CGRect,
        in topology: DisplayTopology
    ) -> DisplayDescriptor?
}
~~~

Exact identifier wins. Replacement candidates must share primary role and are scored by placement, normalized usable-size distance, aspect ratio, and backing scale. With no strong semantic match, choose greatest intersection then nearest center and a stable frame/identifier tie-breaker.

- [ ] **Step 4: Run focused tests and commit**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter DisplayTopologyPolicyTests
git add Sources/Perch/Domain/DisplayTopology.swift Tests/PerchTests/DisplayTopologyPolicyTests.swift
git commit -m "feat: model display topology affinity"
~~~

### Task 2: Topology-Aware Geometry And Stash Intent

**Files:**
- Modify: Sources/Perch/Domain/PanelGeometry.swift
- Modify: Sources/Perch/Platform/PanelGeometryPolicy.swift
- Modify: Sources/Perch/Platform/PanelStashPolicy.swift
- Modify: Tests/PerchTests/PanelGeometryTests.swift
- Modify: Tests/PerchTests/PanelGeometryStoreTests.swift
- Modify: Tests/PerchTests/PanelStashPolicyTests.swift

**Interfaces:**
- Consumes display values from Task 1.
- Produces PanelGeometry.displayAffinity, topology-aware geometry overloads, and PanelStashIntent.

- [ ] **Step 1: Add failing geometry and persistence tests**

Assert capture records affinity, same-ID rearrangement preserves desired size and anchor, changed-ID/scale replacement resolves onto the replacement visible frame, affinity round-trips, and a legacy payload with no displayAffinity key decodes with nil affinity.

- [ ] **Step 2: Add failing stash-intent tests**

~~~swift
struct PanelStashIntent: Equatable, Sendable {
    let side: PanelStashSide
    let verticalFraction: CGFloat
    let displayAffinity: DisplayAffinity?
}
~~~

Assert that side and normalized vertical intent survive disconnect, rearrangement, and strong replacement matching while effective handle frames remain inside visibleFrame.

- [ ] **Step 3: Run focused tests and verify failure**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PanelGeometryTests|PanelGeometryStoreTests|PanelStashPolicyTests'
~~~

- [ ] **Step 4: Implement compatible geometry and stash overloads**

Add optional displayAffinity to PanelGeometry, advance currentVersion to 2, and
decode version 1 as a migrated version 2 value with nil affinity. Reject every
other unsupported version. Add:

~~~swift
static func capture(
    frame: CGRect,
    topology: DisplayTopology,
    desiredContentSize: CGSize? = nil,
    anchor: PanelFrameAnchor? = nil,
    contentRectForFrameRect: (CGRect) -> CGRect
) -> PanelGeometry?

static func resolvedFrame(
    for geometry: PanelGeometry,
    topology: DisplayTopology,
    minimumContentSize: CGSize,
    frameForContentRect: (CGRect) -> CGRect
) -> CGRect
~~~

Retain CGRect-array overloads as wrappers. Add stash intent capture and remapping functions using a clamped 0...1 vertical fraction.

- [ ] **Step 5: Run focused tests and commit**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PanelGeometryTests|PanelGeometryStoreTests|PanelStashPolicyTests'
git add Sources/Perch/Domain/PanelGeometry.swift Sources/Perch/Platform/PanelGeometryPolicy.swift Sources/Perch/Platform/PanelStashPolicy.swift Tests/PerchTests/PanelGeometryTests.swift Tests/PerchTests/PanelGeometryStoreTests.swift Tests/PerchTests/PanelStashPolicyTests.swift
git commit -m "feat: preserve geometry across display changes"
~~~

### Task 3: Pure Revision-Gated Panel Decisions

**Files:**
- Create: Sources/Perch/Platform/PanelTopologyPolicy.swift
- Create: Tests/PerchTests/PanelTopologyPolicyTests.swift

**Interfaces:**
- Consumes committed geometry, stash intent, and topology.
- Produces PanelTopologyPresentation, PanelTopologyDecision, and PanelTopologyPolicy.resolve.

- [ ] **Step 1: Write failing decision tests**

Cover visible, stashed, expanded, and hidden decisions; empty topologies; duplicate revisions; revision 3 followed by stale revision 2; and preferred-size restoration after a small fallback.

~~~swift
enum PanelTopologyPresentation: Equatable, Sendable {
    case visible
    case stashed(PanelStashIntent)
    case expanded
    case hidden
}

struct PanelTopologyDecision: Equatable, Sendable {
    let acceptedRevision: UInt64
    let panelFrame: CGRect?
    let panelFrameShouldDisplay: Bool
    let stashPlacement: PanelStashPlacement?
}
~~~

- [ ] **Step 2: Run tests and verify failure**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelTopologyPolicyTests
~~~

- [ ] **Step 3: Implement the pure reducer**

~~~swift
enum PanelTopologyPolicy {
    static func resolve(
        committedGeometry: PanelGeometry?,
        currentPanelFrame: CGRect,
        presentation: PanelTopologyPresentation,
        lastAcceptedRevision: UInt64,
        topology: DisplayTopology,
        minimumContentSize: CGSize,
        frameForContentRect: (CGRect) -> CGRect
    ) -> PanelTopologyDecision?
}
~~~

Return nil for duplicate/stale revisions. Accept but do not move on an empty snapshot. Resolve visible/hidden frames, remap only the handle while stashed, and leave the frame to AppKit while expanded.

- [ ] **Step 4: Run tests and commit**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PanelTopologyPolicyTests
git add Sources/Perch/Platform/PanelTopologyPolicy.swift Tests/PerchTests/PanelTopologyPolicyTests.swift
git commit -m "feat: resolve panel topology transitions"
~~~

### Task 4: AppKit Observation And Coordinator Reconciliation

**Files:**
- Create: Sources/Perch/Platform/AppKitDisplayTopologyObserver.swift
- Modify: Sources/Perch/Platform/PiPPanelCoordinator.swift
- Modify: Tests/PerchTests/PinCoordinatorTests.swift

**Interfaces:**
- Consumes pure decisions from Task 3.
- Produces revisioned observation and PiPPanelCoordinator.applyDisplayTopology for deterministic tests.

- [ ] **Step 1: Add failing coordinator regressions**

Assert visible disconnect/reconnect and rearrangement move one panel; stashed updates re-present the same handle without presenting the panel; hidden updates set a non-displaying frame; expanded updates preserve the expanded frame; stale revisions produce no operation; and page activation/reselection/reload/show/hide counts never change solely from topology.

- [ ] **Step 2: Run coordinator tests and verify failure**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PinCoordinatorTests
~~~

- [ ] **Step 3: Implement the AppKit adapter**

~~~swift
@MainActor
protocol DisplayTopologyObserving: AnyObject {
    var currentTopology: DisplayTopology { get }
    func start(_ handler: @escaping @MainActor (DisplayTopology) -> Void)
    func stop()
}
~~~

The concrete adapter maps NSScreenNumber to UInt32, samples frame, visibleFrame, scale and primary status, increments revision before delivery, and removes its token in stop/deinit.

- [ ] **Step 4: Reconcile topology in the coordinator**

Replace the direct screen notification token with the adapter. Keep reclampPanelFrame as a compatibility wrapper. Track activeStashIntent and lastAcceptedTopologyRevision. Resolve internal representation in this order: expanded visible panel, visible panel, visible handle, otherwise hidden. Apply frames using the decision display flag and re-present placements through the existing handle. Use topology for capture, restore, sizing, move, corner snap, and stash. Never call page-loader methods from applyDisplayTopology.

- [ ] **Step 5: Run focused tests and commit**

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PinCoordinatorTests|PiPPanelGeometryTests|PanelTopologyPolicyTests'
git add Sources/Perch/Platform/AppKitDisplayTopologyObserver.swift Sources/Perch/Platform/PiPPanelCoordinator.swift Tests/PerchTests/PinCoordinatorTests.swift
git commit -m "feat: reconcile panel on screen notifications"
~~~

### Task 5: Manual Matrix, Full Verification, And Delivery

**Files:**
- Modify: docs/MANUAL_TEST_MATRIX.md

- [ ] **Step 1: Add two-display evidence rows**

Cover visible/stashed/zoomed/hidden disconnect, same-display reconnect, changed scale/resolution, left/right rearrangement, and event-order stress. Each row checks retained edits/selection/scroll, one panel, at most one handle, no system-UI overlap, and no reload.

- [ ] **Step 2: Run formatting and full Swift validation**

~~~sh
git diff --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
~~~

- [ ] **Step 3: Build, stage, launch, and verify**

Run pgrep -x Perch first because the build script quits the app. If it is not running:

~~~sh
./script/build_and_run.sh --verify
~~~

Record honestly whether the current hardware permits physical two-display disconnect/reconnect and Spaces evidence.

- [ ] **Step 4: Commit documentation**

~~~sh
git add docs/MANUAL_TEST_MATRIX.md
git commit -m "docs: expand display topology test matrix"
~~~

- [ ] **Step 5: Sync, create a draft PR, and watch CI**

~~~sh
git fetch origin
git rebase origin/master
git push -u origin HEAD
gh pr create --draft --base master --fill
gh pr checks --watch --fail-fast=false
~~~

- [ ] **Step 6: Resolve failures, merge, and verify post-merge CI**

Diagnose failed logs, add focused regressions for code failures, rerun the full suite, push, and repeat until green. Mark ready, merge using an allowed repository method, then watch the merge-commit workflow and confirm origin/master contains the change.
