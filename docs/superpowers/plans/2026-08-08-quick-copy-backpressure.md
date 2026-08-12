# Quick Copy Bounded Backpressure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound Quick Copy's in-memory candidate backlog and make FIFO draining constant-time while preserving accepted selections, source order, explicit failure recovery, and current Accessibility behavior.

**Architecture:** Add a feature-owned, value-semantic `QuickCopyCandidateBuffer` that implements a fixed-capacity circular FIFO without importing UI or platform frameworks. Compose it into `QuickCopyController`, which remains the owner of user-facing backpressure policy: accept candidates while capacity remains, reject only the newest candidate when full, drain every accepted candidate in order, and publish a warning after the accepted backlog finishes. Keep candidate validation in `QuickCopyPolicy`, monitoring/debounce behavior in `AccessibilitySelectionMonitor`, and insertion mechanics behind `QuickCopyInsertionTarget`.

**Tech Stack:** Swift 6.2, macOS 14, Foundation, Combine, AppKit Accessibility APIs, XCTest, Swift Package Manager.

## Global Constraints

- Preserve the Swift 6.2, macOS 14, public API, signing, and entitlement contracts.
- Keep `QuickCopyController`, `QuickCopyMonitoring`, and `QuickCopyInsertionTarget` on `@MainActor`.
- Keep selected text in memory only; never persist it, log it, put it on the clipboard, or include it in telemetry.
- Preserve exact candidate text and FIFO source order for every accepted candidate.
- Count the currently in-flight candidate toward the buffer capacity.
- Use a default capacity of eight candidates; because `QuickCopyPolicy.defaultMaximumUTF8Bytes` is 256 KiB, this bounds retained candidate text to approximately 2 MiB plus collection overhead.
- When the buffer is full, preserve all previously accepted candidates and reject only the newest candidate with the exact warning: `Quick Copy is busy. This selection wasn’t added; try again shortly.`
- Publish a warning received during insertion only after the accepted backlog drains, so the message is not immediately overwritten by the next insertion state.
- Preserve the existing failed-insertion contract: stop monitoring, retain only the candidate whose insertion failed, clear the remaining backlog, and retry that exact candidate only after explicit re-enablement.
- Preserve the current stop, permission-revocation, target-invalidation, and termination behavior; each must release all queued candidate text.
- Do not add a third-party deque package, a new SwiftPM target, or a queue protocol for this single feature.
- Follow TDD and keep the two tasks independently reviewable.
- Validate every Swift task with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

---

## File Structure

- Create `Sources/Perch/Domain/QuickCopyCandidateBuffer.swift` for fixed-capacity circular FIFO storage of `QuickCopyCandidate` values. This type owns storage mechanics only; it does not decide warning copy, monitor state, candidate validity, or retry behavior.
- Create `Tests/PerchTests/QuickCopyCandidateBufferTests.swift` for capacity, FIFO, wraparound, rejection, and clearing invariants.
- Modify `Sources/Perch/Services/QuickCopyController.swift` to replace its array with the buffer and own overflow/user-state behavior.
- Modify `Tests/PerchTests/QuickCopyControllerTests.swift` for bounded bursts, post-drain warnings, recovery after overflow, and session clearing.
- Modify `docs/MANUAL_TEST_MATRIX.md` with real Accessibility/WebKit checks that cannot be proven by unit tests.
- Do not modify `Sources/Perch/Domain/QuickCopy.swift`: `QuickCopyPolicy` continues to validate candidate content independently of storage capacity.
- Do not modify `Sources/Perch/Platform/AccessibilitySelectionMonitor.swift`: producer-side keyboard debouncing remains useful but is not a substitute for consumer-side bounds.
- Do not modify `Sources/Perch/Views/QuickCopyButton.swift`: its existing `.warning(String)` presentation already renders the required state.

## Behavioral Contract

```text
AccessibilitySelectionMonitor
  -> QuickCopyPolicy.decision(candidate, lastAcceptedSequence)
      -> ignore/reject: existing behavior
      -> accept:
          -> buffer has space: enqueue, record sequence, drain FIFO
          -> buffer full: keep buffer unchanged, defer busy warning

Successful insertion
  -> dequeue completed front candidate
      -> another accepted candidate exists: insert it without exposing an idle state
      -> buffer empty: publish deferred warning, otherwise return to armed

Failed insertion
  -> retain failed front candidate separately
  -> clear every other queued candidate
  -> stop monitoring and require explicit retry
```

The buffer is intentionally feature-owned rather than a generic `Queue<Element>`. This keeps the abstraction at the seam the product currently needs, allows the compiler to enforce that it stores only `QuickCopyCandidate`, and avoids creating a shared utility without a second consumer. Its value semantics still make it independently composable and testable.

### Task 1: Add the bounded candidate FIFO

**Files:**
- Create: `Sources/Perch/Domain/QuickCopyCandidateBuffer.swift`
- Create: `Tests/PerchTests/QuickCopyCandidateBufferTests.swift`

**Interfaces:**
- Consumes: `QuickCopyCandidate` from `Sources/Perch/Domain/QuickCopy.swift`.
- Produces: `struct QuickCopyCandidateBuffer: Sendable`.
- Produces: `QuickCopyCandidateBuffer.standardCapacity == 8`.
- Produces: `enum EnqueueResult: Equatable, Sendable { case accepted, atCapacity }`.
- Produces: `init(capacity: Int = standardCapacity)`, normalizing nonpositive capacity to one so the explicit failed-candidate retry invariant always has a slot.
- Produces: read-only `capacity: Int`, `count: Int`, `isEmpty: Bool`, and `front: QuickCopyCandidate?`.
- Produces: `enqueue(_:) -> EnqueueResult`, `dequeue() -> QuickCopyCandidate?`, and `removeAll()`.

- [ ] **Step 1: Write failing FIFO and capacity tests**

Create `Tests/PerchTests/QuickCopyCandidateBufferTests.swift` with exact ordering and wraparound coverage:

```swift
import XCTest
@testable import Perch

final class QuickCopyCandidateBufferTests: XCTestCase {
    func testFIFORejectsNewestCandidateAtCapacityWithoutMutatingAcceptedOrder() {
        var buffer = QuickCopyCandidateBuffer(capacity: 2)
        let alpha = candidate("alpha", sequence: 1)
        let beta = candidate("beta", sequence: 2)
        let gamma = candidate("gamma", sequence: 3)

        XCTAssertEqual(buffer.enqueue(alpha), .accepted)
        XCTAssertEqual(buffer.enqueue(beta), .accepted)
        XCTAssertEqual(buffer.enqueue(gamma), .atCapacity)
        XCTAssertEqual(buffer.capacity, 2)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.front, alpha)
        XCTAssertEqual(buffer.dequeue(), alpha)
        XCTAssertEqual(buffer.dequeue(), beta)
        XCTAssertNil(buffer.dequeue())
    }

    func testFIFOReusesVacatedSlotsAcrossWraparound() {
        var buffer = QuickCopyCandidateBuffer(capacity: 2)
        let alpha = candidate("alpha", sequence: 1)
        let beta = candidate("beta", sequence: 2)
        let gamma = candidate("gamma", sequence: 3)

        XCTAssertEqual(buffer.enqueue(alpha), .accepted)
        XCTAssertEqual(buffer.enqueue(beta), .accepted)
        XCTAssertEqual(buffer.dequeue(), alpha)
        XCTAssertEqual(buffer.enqueue(gamma), .accepted)

        XCTAssertEqual(buffer.dequeue(), beta)
        XCTAssertEqual(buffer.dequeue(), gamma)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRemoveAllReleasesLogicalContentsAndRetainsConfiguredCapacity() {
        var buffer = QuickCopyCandidateBuffer(capacity: 2)
        XCTAssertEqual(buffer.enqueue(candidate("alpha", sequence: 1)), .accepted)
        XCTAssertEqual(buffer.enqueue(candidate("beta", sequence: 2)), .accepted)

        buffer.removeAll()

        XCTAssertEqual(buffer.capacity, 2)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.front)
        XCTAssertEqual(buffer.enqueue(candidate("gamma", sequence: 3)), .accepted)
        XCTAssertEqual(buffer.front?.text, "gamma")
    }

    func testNonpositiveCapacityStillRetainsOneRetrySlot() {
        var buffer = QuickCopyCandidateBuffer(capacity: 0)

        XCTAssertEqual(buffer.capacity, 1)
        XCTAssertEqual(buffer.enqueue(candidate("alpha", sequence: 1)), .accepted)
        XCTAssertEqual(buffer.enqueue(candidate("beta", sequence: 2)), .atCapacity)
    }

    private func candidate(_ text: String, sequence: UInt64) -> QuickCopyCandidate {
        QuickCopyCandidate(
            text: text,
            source: QuickCopySource(processID: 7, applicationName: "Editor"),
            sequence: sequence
        )
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter QuickCopyCandidateBufferTests
```

Expected: compilation fails because `QuickCopyCandidateBuffer` does not exist.

- [ ] **Step 3: Implement the fixed-capacity circular buffer**

Create `Sources/Perch/Domain/QuickCopyCandidateBuffer.swift`:

```swift
import Foundation

struct QuickCopyCandidateBuffer: Sendable {
    enum EnqueueResult: Equatable, Sendable {
        case accepted
        case atCapacity
    }

    static let standardCapacity = 8

    let capacity: Int
    private var storage: [QuickCopyCandidate?]
    private var headIndex = 0
    private(set) var count = 0

    init(capacity: Int = Self.standardCapacity) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: self.capacity)
    }

    var isEmpty: Bool { count == 0 }

    var front: QuickCopyCandidate? {
        guard count > 0 else { return nil }
        return storage[headIndex]
    }

    @discardableResult
    mutating func enqueue(_ candidate: QuickCopyCandidate) -> EnqueueResult {
        guard count < capacity else { return .atCapacity }
        let insertionIndex = (headIndex + count) % capacity
        storage[insertionIndex] = candidate
        count += 1
        return .accepted
    }

    @discardableResult
    mutating func dequeue() -> QuickCopyCandidate? {
        guard count > 0 else { return nil }
        let candidate = storage[headIndex]
        storage[headIndex] = nil
        headIndex = (headIndex + 1) % capacity
        count -= 1
        if count == 0 { headIndex = 0 }
        return candidate
    }

    mutating func removeAll() {
        for index in storage.indices {
            storage[index] = nil
        }
        headIndex = 0
        count = 0
    }
}
```

Setting dequeued and cleared slots to `nil` is part of the privacy contract: the buffer must not retain selected strings after their logical removal.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the same filtered command. Expected: all `QuickCopyCandidateBufferTests` pass.

- [ ] **Step 5: Run the existing Quick Copy tests to confirm the new isolated type has no side effects**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter QuickCopyControllerTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AccessibilitySelectionMonitorTests
```

Expected: both existing suites pass unchanged.

- [ ] **Step 6: Commit the independently tested buffer**

```sh
git add Sources/Perch/Domain/QuickCopyCandidateBuffer.swift Tests/PerchTests/QuickCopyCandidateBufferTests.swift
git commit -m "feat: add bounded Quick Copy candidate buffer"
```

### Task 2: Compose backpressure into the controller

**Files:**
- Modify: `Sources/Perch/Services/QuickCopyController.swift:53-230`
- Modify: `Tests/PerchTests/QuickCopyControllerTests.swift:98-302`
- Modify: `docs/MANUAL_TEST_MATRIX.md`

**Interfaces:**
- Consumes: `QuickCopyCandidateBuffer` from Task 1.
- Preserves: `QuickCopyController.state`, `toggle()`, `disable()`, and `prepareForTermination()`.
- Extends the internal initializer to `init(monitor:target:policy:pendingCandidateCapacity:)`, with `pendingCandidateCapacity: Int = QuickCopyCandidateBuffer.standardCapacity`.
- Produces: `static let busyMessage = "Quick Copy is busy. This selection wasn’t added; try again shortly."`.
- Keeps `QuickCopyPolicy` responsible only for blank/self/duplicate/security/size decisions.
- Keeps the existing `QuickCopyState.warning(String)` UI contract; no view API changes.

- [ ] **Step 1: Write a failing bounded-burst controller test**

Add this test to `QuickCopyControllerTests`:

```swift
func testFullBufferRejectsNewestCandidateDrainsAcceptedFIFOAndWarnsAfterDrain() {
    let monitor = QuickCopyMonitorSpy(accessGranted: true)
    let target = QuickCopyInsertionTargetSpy()
    let controller = QuickCopyController(
        monitor: monitor,
        target: target,
        pendingCandidateCapacity: 2
    )
    let source = QuickCopySource(processID: 7, applicationName: "Editor")
    controller.toggle()
    target.completeRemembering(true)

    monitor.emit(.candidate(QuickCopyCandidate(text: "alpha", source: source, sequence: 1)))
    monitor.emit(.candidate(QuickCopyCandidate(text: "beta", source: source, sequence: 2)))
    monitor.emit(.candidate(QuickCopyCandidate(text: "gamma", source: source, sequence: 3)))

    XCTAssertEqual(target.insertionTexts, ["alpha"])
    XCTAssertEqual(controller.state, .inserting)

    target.completeNextInsertion(true)
    XCTAssertEqual(target.insertionTexts, ["alpha", "beta"])
    XCTAssertEqual(controller.state, .inserting)

    target.completeNextInsertion(true)
    XCTAssertEqual(target.insertionTexts, ["alpha", "beta"])
    XCTAssertEqual(controller.state, .warning(QuickCopyController.busyMessage))

    monitor.emit(.candidate(QuickCopyCandidate(text: "delta", source: source, sequence: 4)))
    XCTAssertEqual(target.insertionTexts, ["alpha", "beta", "delta"])
    target.completeNextInsertion(true)
    XCTAssertEqual(controller.state, .armed)
}
```

This test proves five contracts together: the in-flight candidate counts toward capacity, accepted candidates keep source order, the newest overflow candidate is not inserted, the warning survives until drain completion, and the session remains usable afterward.

- [ ] **Step 2: Write a failing reset/privacy regression test**

Add a second controller test:

```swift
func testDisableClearsQueuedCandidateBeforeAStaleCompletionAndNextSession() {
    let monitor = QuickCopyMonitorSpy(accessGranted: true)
    let target = QuickCopyInsertionTargetSpy()
    let controller = QuickCopyController(
        monitor: monitor,
        target: target,
        pendingCandidateCapacity: 2
    )
    let source = QuickCopySource(processID: 7, applicationName: "Editor")
    controller.toggle()
    target.completeRemembering(true)
    monitor.emit(.candidate(QuickCopyCandidate(text: "alpha", source: source, sequence: 1)))
    monitor.emit(.candidate(QuickCopyCandidate(text: "must be cleared", source: source, sequence: 2)))

    controller.disable()
    target.completeNextInsertion(true)

    controller.toggle()
    target.completeRemembering(true)
    monitor.emit(.candidate(QuickCopyCandidate(text: "new session", source: source, sequence: 3)))

    XCTAssertEqual(target.insertionTexts, ["alpha", "new session"])
    XCTAssertEqual(controller.state, .inserting)
}
```

- [ ] **Step 3: Run the focused controller tests and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter QuickCopyControllerTests
```

Expected: compilation fails because `pendingCandidateCapacity` and `busyMessage` do not exist.

- [ ] **Step 4: Replace the array with the bounded buffer and centralize clearing**

In `QuickCopyController`, replace:

```swift
private var pendingCandidates: [QuickCopyCandidate] = []
```

with:

```swift
static let busyMessage =
    "Quick Copy is busy. This selection wasn’t added; try again shortly."

private var pendingCandidates: QuickCopyCandidateBuffer
```

Extend initialization without changing existing call sites:

```swift
init(
    monitor: any QuickCopyMonitoring,
    target: any QuickCopyInsertionTarget,
    policy: QuickCopyPolicy = QuickCopyPolicy(),
    pendingCandidateCapacity: Int = QuickCopyCandidateBuffer.standardCapacity
) {
    self.monitor = monitor
    self.target = target
    self.policy = policy
    pendingCandidates = QuickCopyCandidateBuffer(capacity: pendingCandidateCapacity)
    monitor.onEvent = { [weak self] event in self?.handle(event) }
    target.onQuickCopyTargetInvalidated = { [weak self] in self?.targetDidInvalidate() }
}
```

Replace every `pendingCandidates.removeAll(keepingCapacity: false)` with `pendingCandidates.removeAll()`. Do not add a second buffer-clearing helper unless another piece of session state is moved with it in the same change.

- [ ] **Step 5: Apply controller-owned overflow policy**

Change accepted-candidate handling to update `lastAcceptedSequence` only after the candidate is retained:

```swift
case .accept:
    switch pendingCandidates.enqueue(candidate) {
    case .accepted:
        lastAcceptedSequence = candidate.sequence
        insertNextCandidateIfNeeded()
    case .atCapacity:
        showWarning(Self.busyMessage)
    }
```

When explicitly retrying `failedCandidate` during `beginEnabling()`, enqueue it into the freshly cleared buffer and start insertion only on `.accepted`. The buffer normalizes capacity to at least one, so `.atCapacity` is defensive rather than expected:

```swift
if let failedCandidate = self.failedCandidate {
    self.failedCandidate = nil
    switch self.pendingCandidates.enqueue(failedCandidate) {
    case .accepted:
        self.insertNextCandidateIfNeeded()
    case .atCapacity:
        self.failedCandidate = failedCandidate
        self.monitor.stop()
        self.state = .failed(Self.staleCursorMessage)
    }
}
```

- [ ] **Step 6: Separate insertion start from queue-drain completion**

Refactor the insertion path so successful completion starts the next accepted candidate directly and publishes a deferred warning only when the buffer becomes empty:

```swift
private func insertNextCandidateIfNeeded() {
    guard state != .inserting, let candidate = pendingCandidates.front else {
        return
    }
    beginInsertion(of: candidate)
}

private func beginInsertion(of candidate: QuickCopyCandidate) {
    guard let target else {
        failInsertion(of: candidate)
        return
    }
    state = .inserting
    target.insertAtSavedEditorCursor(candidate.text) { [weak self] inserted in
        guard let self, self.state == .inserting,
              self.pendingCandidates.front == candidate
        else {
            return
        }
        guard inserted else {
            self.failInsertion(of: candidate)
            return
        }
        _ = self.pendingCandidates.dequeue()
        if let nextCandidate = self.pendingCandidates.front {
            self.beginInsertion(of: nextCandidate)
        } else {
            self.finishCandidateDrain()
        }
    }
}

private func finishCandidateDrain() {
    if let deferredWarningMessage {
        self.deferredWarningMessage = nil
        state = .warning(deferredWarningMessage)
    } else {
        state = .armed
    }
}
```

Keep `showWarning(_:)` unchanged: when insertion is active it writes `deferredWarningMessage`; otherwise it publishes `.warning` immediately. Keep `failInsertion(of:)` clearing the buffer before it stops monitoring, so no nonfailed candidate survives into explicit retry.

- [ ] **Step 7: Run focused tests and preserve all existing state-machine behavior**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter QuickCopyCandidateBufferTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter QuickCopyControllerTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AccessibilitySelectionMonitorTests
```

Expected: all new and existing tests pass. Specifically confirm that the pre-existing stale-cursor test still retries only the failed candidate and the permission/target invalidation tests still stop the monitor.

- [ ] **Step 8: Add manual burst and privacy rows**

Append these rows to `docs/MANUAL_TEST_MATRIX.md`:

```markdown
| Quick Copy armed with a saved Notion cursor; insertion deliberately slowed under a debugger or WebKit pause | Select text in more than eight distinct external-app interactions before the first insertion finishes, then resume WebKit | Previously accepted selections insert once in source order; later overflow selections are not inserted; after the backlog drains, the control says “Quick Copy is busy. This selection wasn’t added; try again shortly.” and a new selection can be inserted normally |  |  | Do not use passwords or sensitive text for this test |
| Quick Copy has one insertion in flight and at least one queued selection | Turn Quick Copy off before the insertion callback completes, then turn it on again and select fresh text | The stale completion has no effect, queued text from the prior session never appears, and only fresh text from the new session is inserted |  |  | Confirm the clipboard remains unchanged |
```

- [ ] **Step 9: Run the complete Swift suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: the full suite passes with zero failures. No Node commands are required because this plan does not modify `Web/QuickCaptureEditor`.

- [ ] **Step 10: Review dependency direction and scope before committing**

Confirm all of the following in the diff:

```text
QuickCopyCandidateBuffer -> QuickCopyCandidate only
QuickCopyController -> buffer + existing monitoring/insertion ports
AccessibilitySelectionMonitor -> unchanged
QuickCopyButton -> unchanged
Package.swift -> unchanged
No selected text appears in logs, persisted models, docs examples beyond fixed synthetic strings, or telemetry
```

Run `git diff --check` and require no whitespace errors.

- [ ] **Step 11: Commit controller composition and documentation**

```sh
git add Sources/Perch/Services/QuickCopyController.swift Tests/PerchTests/QuickCopyControllerTests.swift docs/MANUAL_TEST_MATRIX.md
git commit -m "fix: bound Quick Copy insertion backlog"
```

## Acceptance Criteria

- A Quick Copy session retains no more than eight candidates, including the active insertion.
- Enqueue and dequeue are O(1), including across circular-buffer wraparound.
- The ninth candidate is rejected without evicting or reordering the eight accepted candidates.
- The busy warning remains visible after the accepted backlog drains instead of flashing between insertions.
- A new candidate can be accepted after the warning without toggling Quick Copy off and on.
- Disabling, terminating, losing permission, invalidating the target, or failing insertion releases all queued candidate text according to the existing state-machine contract.
- Explicit retry retains and retries only the exact candidate whose insertion failed.
- No new dependency, target, public API, persistence, logging, clipboard access, or platform permission is introduced.
- Focused buffer, controller, and Accessibility monitor tests pass, followed by the full Swift suite.

## Out of Scope

- Changing the 250 ms Accessibility keyboard debounce.
- Coalescing distinct selections or silently replacing an accepted candidate with a newer one.
- Pausing and restarting the Accessibility monitor at high/low watermarks.
- Persisting pending selections across app restarts or Quick Copy sessions.
- Adding queue-length UI, settings, telemetry, or a user-configurable capacity.
- Extracting Quick Copy into a separate SwiftPM target before another feature boundary justifies that module.
