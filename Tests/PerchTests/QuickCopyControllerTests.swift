import XCTest
@testable import Perch

@MainActor
final class QuickCopyControllerTests: XCTestCase {
    func testPolicyIgnoresBlankSelfAndDuplicateCandidatesWithoutChangingExactText() {
        let policy = QuickCopyPolicy(ownProcessID: 42)
        let external = QuickCopySource(
            processID: 7,
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor"
        )

        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(text: " \n", source: external, sequence: 1),
                lastAcceptedSequence: nil
            ),
            .ignore
        )
        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(
                    text: "alpha",
                    source: QuickCopySource(
                        processID: 42,
                        bundleIdentifier: "com.fantomsuj.Perch",
                        applicationName: "Perch"
                    ),
                    sequence: 2
                ),
                lastAcceptedSequence: nil
            ),
            .ignore
        )
        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(text: "  alpha\n", source: external, sequence: 3),
                lastAcceptedSequence: nil
            ),
            .accept
        )
        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(text: "beta", source: external, sequence: 3),
                lastAcceptedSequence: 3
            ),
            .ignore
        )
    }

    func testPolicyRejectsSecureUnsupportedAndOversizedSources() {
        let policy = QuickCopyPolicy(maximumUTF8Bytes: 5, ownProcessID: 42)

        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(
                    text: "secret",
                    source: QuickCopySource(
                        processID: 7,
                        applicationName: "Passwords",
                        isSecure: true
                    ),
                    sequence: 1
                ),
                lastAcceptedSequence: nil
            ),
            .reject(.secureField)
        )
        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(
                    text: "alpha",
                    source: QuickCopySource(
                        processID: 7,
                        applicationName: "Canvas",
                        supportsSelectedText: false
                    ),
                    sequence: 2
                ),
                lastAcceptedSequence: nil
            ),
            .reject(.unsupportedSource("Canvas"))
        )
        XCTAssertEqual(
            policy.decision(
                for: QuickCopyCandidate(
                    text: "123456",
                    source: QuickCopySource(processID: 7, applicationName: "Editor"),
                    sequence: 3
                ),
                lastAcceptedSequence: nil
            ),
            .reject(.oversized)
        )
    }

    func testEnablingRequiresNotionCursorBeforeRequestingAccessibility() {
        let monitor = QuickCopyMonitorSpy(accessGranted: true)
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)

        controller.toggle()
        target.completeRemembering(false)

        XCTAssertEqual(controller.state, .failed("Click in the Notion page first."))
        XCTAssertEqual(monitor.accessRequestCount, 0)
        XCTAssertEqual(monitor.startCount, 0)
    }

    func testDeniedAccessibilityShowsPermissionStateWithoutStartingMonitor() {
        let monitor = QuickCopyMonitorSpy(accessGranted: false)
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)

        controller.toggle()
        target.completeRemembering(true)

        XCTAssertEqual(controller.state, .permissionNeeded)
        XCTAssertEqual(monitor.accessRequestCount, 1)
        XCTAssertEqual(monitor.startCount, 0)
    }

    func testPermissionRevokedDuringMonitorStartupCannotBeOverwrittenAsArmed() {
        let monitor = QuickCopyMonitorSpy(accessGranted: true)
        monitor.eventOnStart = .permissionRevoked
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)

        controller.toggle()
        target.completeRemembering(true)

        XCTAssertEqual(controller.state, .permissionNeeded)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testCandidatesInsertSeriallyAndDuplicateSequenceIsIgnored() {
        let monitor = QuickCopyMonitorSpy(accessGranted: true)
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)
        let source = QuickCopySource(processID: 7, applicationName: "Editor")
        controller.toggle()
        target.completeRemembering(true)

        monitor.emit(.candidate(QuickCopyCandidate(text: "alpha", source: source, sequence: 1)))
        monitor.emit(.candidate(QuickCopyCandidate(text: "beta", source: source, sequence: 2)))
        monitor.emit(.candidate(QuickCopyCandidate(text: "duplicate", source: source, sequence: 2)))

        XCTAssertEqual(target.insertionTexts, ["alpha"])
        XCTAssertEqual(controller.state, .inserting)

        target.completeNextInsertion(true)
        XCTAssertEqual(target.insertionTexts, ["alpha", "beta"])
        target.completeNextInsertion(true)

        XCTAssertEqual(controller.state, .armed)
        XCTAssertEqual(monitor.startCount, 1)
    }

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

    func testWarningDuringInsertionDoesNotRetryCompletedCandidate() {
        let monitor = QuickCopyMonitorSpy(accessGranted: true)
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)
        let source = QuickCopySource(processID: 7, applicationName: "Editor")
        controller.toggle()
        target.completeRemembering(true)
        monitor.emit(
            .candidate(QuickCopyCandidate(text: "alpha", source: source, sequence: 1))
        )

        monitor.emit(.unsupportedSource("Canvas"))
        target.completeNextInsertion(true)

        XCTAssertEqual(target.insertionTexts, ["alpha"])
        XCTAssertEqual(
            controller.state,
            .warning("Canvas doesn’t expose selected text.")
        )

        monitor.emit(
            .candidate(QuickCopyCandidate(text: "beta", source: source, sequence: 2))
        )
        XCTAssertEqual(target.insertionTexts, ["alpha", "beta"])
    }

    func testStaleInsertionStopsMonitoringAndRetriesOnlyFailedCandidateExplicitly() {
        let monitor = QuickCopyMonitorSpy(accessGranted: true)
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)
        controller.toggle()
        target.completeRemembering(true)
        monitor.emit(
            .candidate(
                QuickCopyCandidate(
                    text: "retry me",
                    source: QuickCopySource(processID: 7, applicationName: "Editor"),
                    sequence: 1
                )
            )
        )

        target.completeNextInsertion(false)

        XCTAssertEqual(controller.state, .failed("The Notion cursor changed. Click in the page, then retry."))
        XCTAssertEqual(monitor.stopCount, 1)

        controller.toggle()
        target.completeRemembering(true)

        XCTAssertEqual(target.insertionTexts, ["retry me", "retry me"])
        XCTAssertEqual(controller.state, .inserting)
    }

    func testTargetInvalidationAndPermissionRevocationStopAndClearSession() {
        let monitor = QuickCopyMonitorSpy(accessGranted: true)
        let target = QuickCopyInsertionTargetSpy()
        let controller = QuickCopyController(monitor: monitor, target: target)
        controller.toggle()
        target.completeRemembering(true)

        target.invalidate()

        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(monitor.stopCount, 1)

        controller.toggle()
        target.completeRemembering(true)
        monitor.emit(.permissionRevoked)

        XCTAssertEqual(controller.state, .permissionNeeded)
        XCTAssertEqual(monitor.stopCount, 2)
    }
}

@MainActor
private final class QuickCopyMonitorSpy: QuickCopyMonitoring {
    var onEvent: (@MainActor (QuickCopyMonitorEvent) -> Void)?
    var accessGranted: Bool
    var eventOnStart: QuickCopyMonitorEvent?
    private(set) var accessRequestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(accessGranted: Bool) {
        self.accessGranted = accessGranted
    }

    func requestAccessibilityAccess() -> Bool {
        accessRequestCount += 1
        return accessGranted
    }

    func start() {
        startCount += 1
        if let eventOnStart {
            onEvent?(eventOnStart)
        }
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ event: QuickCopyMonitorEvent) {
        onEvent?(event)
    }
}

@MainActor
private final class QuickCopyInsertionTargetSpy: QuickCopyInsertionTarget {
    var onQuickCopyTargetInvalidated: (@MainActor () -> Void)?
    private var rememberCompletions: [(@MainActor (Bool) -> Void)] = []
    private var insertionCompletions: [(@MainActor (Bool) -> Void)] = []
    private(set) var insertionTexts: [String] = []

    func rememberCurrentEditorCursor(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        rememberCompletions.append(completion)
    }

    func insertAtSavedEditorCursor(
        _ text: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        insertionTexts.append(text)
        insertionCompletions.append(completion)
    }

    func completeRemembering(_ remembered: Bool) {
        rememberCompletions.removeFirst()(remembered)
    }

    func completeNextInsertion(_ inserted: Bool) {
        insertionCompletions.removeFirst()(inserted)
    }

    func invalidate() {
        onQuickCopyTargetInvalidated?()
    }
}
