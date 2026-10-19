import Combine
import os
import XCTest
@testable import Perch

@MainActor
final class AgentStreamControllerTests: XCTestCase {
    func testCreateDoesNotCaptureCursorAndStartsReceiving() throws {
        let target = AgentStreamTargetSpy(available: true, pageID: "page-1")
        let notifier = AgentStreamNotifierSpy()
        let controller = AgentStreamController(target: target, notifier: notifier)

        let result = try controller.create(
            AgentStreamCreateRequest(client: "cursor", label: "Cursor", idempotencyKey: "k1")
        )

        XCTAssertEqual(result.snapshot.phase, .receiving)
        XCTAssertEqual(result.snapshot.label, "Cursor")
        XCTAssertEqual(result.snapshot.contentType, .markdown)
        XCTAssertEqual(result.snapshot.nextSequence, 0)
        XCTAssertEqual(target.rememberCount, 0)
        XCTAssertEqual(notifier.readyLabels, [])
    }

    func testSecondCreateWhileActiveReturnsStreamActive() throws {
        let controller = makeController()
        _ = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        )

        XCTAssertThrowsError(
            try controller.create(
                AgentStreamCreateRequest(client: "b", idempotencyKey: "2")
            )
        ) { error in
            XCTAssertEqual((error as? AgentStreamError)?.code, .streamActive)
        }
    }

    func testCreateIdempotencyKeyReturnsSameStream() throws {
        let controller = makeController()
        let first = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "same")
        )
        let second = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "same")
        )
        XCTAssertEqual(first.snapshot.id, second.snapshot.id)
    }

    func testOrderedAppendIdempotentRetryAndSequenceConflict() throws {
        let controller = makeController()
        let created = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        )
        let id = created.snapshot.id

        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "# Hello\n")
        )
        let retry = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "# Hello\n")
        )
        XCTAssertEqual(retry.assembledText, "# Hello\n")
        XCTAssertEqual(retry.nextSequence, 1)

        XCTAssertThrowsError(
            try controller.append(
                streamID: id,
                chunk: AgentStreamChunk(sequence: 2, text: "skip")
            )
        ) { error in
            let streamError = error as? AgentStreamError
            XCTAssertEqual(streamError?.code, .sequenceMismatch)
            XCTAssertEqual(streamError?.expectedSequence, 1)
        }

        let next = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 1, text: "world")
        )
        XCTAssertEqual(next.assembledText, "# Hello\nworld")
    }

    func testCompleteMovesToReadyAndNotifiesWithoutInserting() throws {
        let target = AgentStreamTargetSpy()
        let notifier = AgentStreamNotifierSpy()
        let controller = AgentStreamController(target: target, notifier: notifier)
        let id = try controller.create(
            AgentStreamCreateRequest(client: "codex", label: "Codex", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "## Notes")
        )

        let ready = try controller.complete(streamID: id)

        XCTAssertEqual(ready.phase, .ready)
        XCTAssertTrue(ready.canAccept)
        XCTAssertEqual(notifier.readyLabels, ["Codex"])
        XCTAssertEqual(target.pasteCount, 0)
        XCTAssertEqual(
            controller.overlayPresentation,
            .ready(label: "Codex", text: "## Notes", contentType: .markdown)
        )
    }

    func testAcceptCapturesCursorThenPastesMarkdown() throws {
        let target = AgentStreamTargetSpy()
        let controller = AgentStreamController(
            target: target,
            notifier: AgentStreamNotifierSpy()
        )
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "- item")
        )
        _ = try controller.complete(streamID: id)

        controller.accept()
        XCTAssertEqual(controller.snapshot?.phase, .inserting)
        XCTAssertEqual(target.rememberCount, 1)

        target.completeRemembering(true)
        XCTAssertEqual(target.pasteTexts, ["- item"])
        target.completeNextPaste(true)

        XCTAssertEqual(controller.snapshot?.phase, .inserted)
        XCTAssertEqual(controller.snapshot?.assembledText, "")
    }

    func testAcceptWithoutCursorKeepsTextAndAllowsRetry() throws {
        let target = AgentStreamTargetSpy()
        let controller = AgentStreamController(
            target: target,
            notifier: AgentStreamNotifierSpy()
        )
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "keep me")
        )
        _ = try controller.complete(streamID: id)

        controller.accept()
        target.completeRemembering(false)

        XCTAssertEqual(controller.snapshot?.phase, .failed)
        XCTAssertEqual(controller.snapshot?.assembledText, "keep me")
        XCTAssertTrue(controller.snapshot?.canAccept == true)
        XCTAssertEqual(target.pasteCount, 0)

        controller.accept()
        target.completeRemembering(true)
        target.completeNextPaste(true)
        XCTAssertEqual(controller.snapshot?.phase, .inserted)
    }

    func testCancelDuringReceivingClearsOverlayAndBlocksChunks() throws {
        let controller = makeController()
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.cancel(streamID: id)

        XCTAssertEqual(controller.snapshot?.phase, .cancelled)
        XCTAssertEqual(controller.overlayPresentation, .hidden)
        // Cancel clears showsOverlay, so presentation policy is hidden.
        XCTAssertEqual(
            AgentStreamOverlayPresentation.from(snapshot: controller.snapshot),
            .hidden
        )

        XCTAssertThrowsError(
            try controller.append(
                streamID: id,
                chunk: AgentStreamChunk(sequence: 0, text: "late")
            )
        ) { error in
            XCTAssertEqual((error as? AgentStreamError)?.code, .streamGone)
        }
    }

    func testChunkSizeLimit() throws {
        let limits = AgentStreamLimits(
            maxChunkUTF8Bytes: 4,
            maxAssembledUTF8Bytes: 100,
            maxHeaderUTF8Bytes: 16 * 1_024,
            maxBodyUTF8Bytes: 64 * 1_024,
            maxRequestsPerSecond: 30,
            inactiveExpiration: .seconds(600),
            terminalRetention: .seconds(600),
            readyRetention: .seconds(1_800)
        )
        let controller = AgentStreamController(
            target: AgentStreamTargetSpy(),
            notifier: AgentStreamNotifierSpy(),
            limits: limits
        )
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id

        XCTAssertThrowsError(
            try controller.append(
                streamID: id,
                chunk: AgentStreamChunk(sequence: 0, text: "12345")
            )
        ) { error in
            XCTAssertEqual((error as? AgentStreamError)?.code, .payloadTooLarge)
        }
    }

    func testPresentationSurfacesAcceptForReadyState() {
        let snapshot = AgentStreamSnapshot(
            id: UUID(),
            label: "Agent",
            client: "agent",
            contentType: .markdown,
            phase: .ready,
            assembledText: "**bold**",
            nextSequence: 1,
            opaquePageID: nil,
            errorMessage: nil,
            canAccept: true,
            showsOverlay: true
        )
        XCTAssertEqual(
            AgentStreamOverlayPresentation.from(snapshot: snapshot),
            .ready(label: "Agent", text: "**bold**", contentType: .markdown)
        )
        XCTAssertEqual(
            AgentStreamAccessibilityLabels.accept,
            "Accept and paste into Notion"
        )
    }

    func testAcceptAndDismissIgnoreStaleStreamIDs() throws {
        let target = AgentStreamTargetSpy()
        let controller = AgentStreamController(
            target: target,
            notifier: AgentStreamNotifierSpy()
        )
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "keep")
        )
        _ = try controller.complete(streamID: id)
        XCTAssertEqual(controller.snapshot?.phase, .ready)

        controller.accept(streamID: UUID())
        XCTAssertEqual(controller.snapshot?.phase, .ready)
        XCTAssertEqual(target.rememberCount, 0)

        controller.dismissFromOverlay(streamID: UUID())
        XCTAssertEqual(controller.snapshot?.phase, .ready)
        XCTAssertEqual(
            controller.overlayPresentation,
            .ready(label: "a", text: "keep", contentType: .markdown)
        )

        controller.accept(streamID: id)
        XCTAssertEqual(controller.snapshot?.phase, .inserting)
    }

    func testScheduledExpiryExpiresReadyStreamWithoutFurtherAPITraffic() throws {
        final class ClockBox: @unchecked Sendable {
            var now = Date(timeIntervalSince1970: 1_000)
        }
        let clockBox = ClockBox()
        var scheduled: [(Duration, @MainActor () -> Void)] = []
        let limits = AgentStreamLimits(
            maxChunkUTF8Bytes: 32 * 1_024,
            maxAssembledUTF8Bytes: 512 * 1_024,
            maxHeaderUTF8Bytes: 16 * 1_024,
            maxBodyUTF8Bytes: 64 * 1_024,
            maxRequestsPerSecond: 30,
            inactiveExpiration: .seconds(600),
            terminalRetention: .seconds(600),
            readyRetention: .seconds(30)
        )
        let controller = AgentStreamController(
            target: AgentStreamTargetSpy(),
            notifier: AgentStreamNotifierSpy(),
            limits: limits,
            clock: { clockBox.now },
            receiptScheduler: { delay, operation in
                scheduled.append((delay, operation))
                return {}
            }
        )
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.complete(streamID: id)
        XCTAssertEqual(controller.snapshot?.phase, .ready)
        XCTAssertTrue(scheduled.contains(where: { $0.0 == limits.readyRetention }))

        clockBox.now = clockBox.now.addingTimeInterval(31)
        let readyExpiry = try XCTUnwrap(
            scheduled.last(where: { $0.0 == limits.readyRetention })
        )
        readyExpiry.1()
        XCTAssertEqual(controller.snapshot?.phase, .expired)
        XCTAssertEqual(controller.overlayPresentation, .hidden)
    }

    func testReceivingOverlayRefreshesAtMostOncePerInterval() throws {
        let harness = ThrottleHarness()
        let controller = harness.makeController()
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        XCTAssertEqual(controller.overlayPresentation, harness.receiving(""))

        var publicationCount = 0
        let observation = controller.objectWillChange.sink { _ in
            publicationCount += 1
        }
        for sequence in 0..<5 {
            _ = try controller.append(
                streamID: id,
                chunk: AgentStreamChunk(sequence: sequence, text: "x")
            )
        }

        // API callers always see the full text; the overlay waits for the next refresh.
        XCTAssertEqual(controller.snapshot?.assembledText, "xxxxx")
        XCTAssertEqual(controller.overlayPresentation, harness.receiving(""))
        XCTAssertEqual(publicationCount, 0)
        XCTAssertEqual(harness.refreshes.count, 1)
        XCTAssertEqual(
            harness.refreshes.first?.delay,
            AgentStreamController.overlayRefreshInterval
        )

        harness.advance(by: 0.1)
        try XCTUnwrap(harness.refreshes.first).run()

        XCTAssertEqual(controller.overlayPresentation, harness.receiving("xxxxx"))
        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(observation) {}
    }

    func testAppendAfterQuietIntervalRefreshesOverlayAtOnce() throws {
        let harness = ThrottleHarness()
        let controller = harness.makeController()
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id

        harness.advance(by: 0.25)
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "# Hi")
        )

        XCTAssertEqual(controller.overlayPresentation, harness.receiving("# Hi"))
        XCTAssertTrue(harness.refreshes.isEmpty)
    }

    func testCompleteShowsFullTextWithoutWaitingForThrottle() throws {
        let harness = ThrottleHarness()
        let controller = harness.makeController()
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "- one")
        )
        XCTAssertEqual(controller.overlayPresentation, harness.receiving(""))

        _ = try controller.complete(streamID: id)
        XCTAssertEqual(
            controller.overlayPresentation,
            .ready(label: "a", text: "- one", contentType: .markdown)
        )

        // A refresh that was already queued must not bring back the receiving state.
        try XCTUnwrap(harness.refreshes.first).run()
        XCTAssertEqual(
            controller.overlayPresentation,
            .ready(label: "a", text: "- one", contentType: .markdown)
        )
    }

    func testRetriedChunkReturnsFullTextWhileReceiving() throws {
        let controller = makeController()
        let id = try controller.create(
            AgentStreamCreateRequest(client: "a", idempotencyKey: "1")
        ).snapshot.id
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 0, text: "one ")
        )
        _ = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 1, text: "two")
        )

        let retry = try controller.append(
            streamID: id,
            chunk: AgentStreamChunk(sequence: 1, text: "two")
        )

        XCTAssertEqual(retry.assembledText, "one two")
        XCTAssertEqual(try controller.stream(id: id).assembledText, "one two")
    }

    private func makeController() -> AgentStreamController {
        AgentStreamController(
            target: AgentStreamTargetSpy(),
            notifier: AgentStreamNotifierSpy()
        )
    }
}

@MainActor
private final class AgentStreamTargetSpy: AgentStreamTarget {
    var isAgentStreamTargetAvailable: Bool
    var agentStreamOpaquePageID: String?
    private(set) var rememberCount = 0
    private(set) var pasteCount = 0
    private(set) var pasteTexts: [String] = []

    private var rememberCompletion: (@MainActor (Bool) -> Void)?
    private var pasteCompletion: (@MainActor (Bool) -> Void)?

    init(available: Bool = true, pageID: String? = "page") {
        isAgentStreamTargetAvailable = available
        agentStreamOpaquePageID = pageID
    }

    func rememberCurrentEditorCursor(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        rememberCount += 1
        rememberCompletion = completion
    }

    func pasteMarkdownAtSavedEditorCursor(
        _ markdown: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        pasteCount += 1
        pasteTexts.append(markdown)
        pasteCompletion = completion
    }

    func completeRemembering(_ value: Bool) {
        let completion = rememberCompletion
        rememberCompletion = nil
        completion?(value)
    }

    func completeNextPaste(_ value: Bool) {
        let completion = pasteCompletion
        pasteCompletion = nil
        completion?(value)
    }
}

@MainActor
private final class AgentStreamNotifierSpy: AgentStreamNotifying {
    private(set) var readyLabels: [String] = []
    private(set) var clearCount = 0

    func notifyStreamReady(label: String, streamID: UUID) {
        readyLabels.append(label)
    }

    func clearStreamNotifications() {
        clearCount += 1
    }
}

/// Drives the overlay throttle with a fixed clock and captured refreshes.
@MainActor
private final class ThrottleHarness {
    struct Scheduled {
        let delay: Duration
        let run: @MainActor () -> Void
    }

    private let now = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
    private(set) var scheduled: [Scheduled] = []

    /// Scheduled overlay refreshes; expiry timers use much longer delays.
    var refreshes: [Scheduled] {
        scheduled.filter { $0.delay <= AgentStreamController.overlayRefreshInterval }
    }

    func makeController() -> AgentStreamController {
        let now = now
        return AgentStreamController(
            target: AgentStreamTargetSpy(),
            notifier: AgentStreamNotifierSpy(),
            clock: { now.withLock { $0 } },
            receiptScheduler: { [weak self] delay, operation in
                self?.scheduled.append(Scheduled(delay: delay, run: operation))
                return {}
            }
        )
    }

    func advance(by seconds: TimeInterval) {
        now.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    func receiving(_ text: String) -> AgentStreamOverlayPresentation {
        .receiving(label: "a", text: text, contentType: .markdown, isStreaming: true)
    }
}
