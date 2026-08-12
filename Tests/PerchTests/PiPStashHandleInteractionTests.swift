import AppKit
import XCTest
@testable import Perch

@MainActor
final class PiPStashHandleInteractionTests: XCTestCase {
    func testValidExternalDragPublishesFrozenCandidateAndPerformsItOnce() throws {
        let first = try makeDrop(
            pageID: "0123456789abcdef0123456789abcdef",
            sourceLabel: "Roadmap"
        )
        let later = try makeDrop(
            pageID: "fedcba9876543210fedcba9876543210",
            sourceLabel: "Later"
        )
        let candidate = DropCandidate(first)
        var activationCount = 0
        var changes: [NotionPageDrop?] = []
        var performed: [NotionPageDrop] = []
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { .zero },
            onActivate: { activationCount += 1 },
            onDragEnded: { _ in },
            onDropCandidateChanged: { changes.append($0) },
            onDropPerformed: { performed.append($0) }
        )
        let firstSnapshot = PiPStashHandleDragSnapshot(
            sequenceNumber: 41,
            candidate: candidate.value,
            sourceOperationMask: .copy
        )

        XCTAssertTrue(interaction.registeredDraggedTypes.contains(.URL))
        XCTAssertTrue(interaction.registeredDraggedTypes.contains(.string))
        XCTAssertEqual(interaction.draggingEntered(snapshot: firstSnapshot), .copy)
        XCTAssertEqual(changes, [first])
        XCTAssertEqual(activationCount, 0)

        candidate.value = later
        let laterSnapshot = PiPStashHandleDragSnapshot(
            sequenceNumber: 41,
            candidate: candidate.value,
            sourceOperationMask: .copy
        )
        XCTAssertEqual(interaction.draggingUpdated(snapshot: laterSnapshot), .copy)
        XCTAssertEqual(changes, [first])
        XCTAssertTrue(interaction.prepareForDragOperation(sequenceNumber: 41))
        XCTAssertTrue(interaction.performDragOperation(sequenceNumber: 41))
        XCTAssertFalse(interaction.performDragOperation(sequenceNumber: 41))
        XCTAssertEqual(changes, [first, nil])
        XCTAssertEqual(performed, [first])
        XCTAssertEqual(activationCount, 0)
    }

    func testInvalidExternalDragIsInert() {
        var changes: [NotionPageDrop?] = []
        var performed: [NotionPageDrop] = []
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { .zero },
            onActivate: {},
            onDragEnded: { _ in },
            onDropCandidateChanged: { changes.append($0) },
            onDropPerformed: { performed.append($0) }
        )
        let snapshot = PiPStashHandleDragSnapshot(
            sequenceNumber: 42,
            candidate: nil,
            sourceOperationMask: .copy
        )

        XCTAssertEqual(interaction.draggingEntered(snapshot: snapshot), NSDragOperation())
        XCTAssertFalse(interaction.prepareForDragOperation(sequenceNumber: 42))
        XCTAssertFalse(interaction.performDragOperation(sequenceNumber: 42))
        XCTAssertTrue(changes.isEmpty)
        XCTAssertTrue(performed.isEmpty)
    }

    func testExternalDragResetCallbacksClearPreview() throws {
        let drop = try makeDrop(
            pageID: "0123456789abcdef0123456789abcdef",
            sourceLabel: "Roadmap"
        )
        let reset: [(PiPStashHandleInteractionView) -> Void] = [
            { view in view.draggingExited() },
            { view in view.concludeDragOperation() },
            { view in view.draggingEnded() }
        ]

        for resetDrag in reset {
            var changes: [NotionPageDrop?] = []
            let interaction = PiPStashHandleInteractionView(
                pointerLocation: { .zero },
                onActivate: {},
                onDragEnded: { _ in },
                onDropCandidateChanged: { changes.append($0) }
            )
            let snapshot = PiPStashHandleDragSnapshot(
                sequenceNumber: 43,
                candidate: drop,
                sourceOperationMask: .copy
            )
            XCTAssertEqual(interaction.draggingEntered(snapshot: snapshot), .copy)

            resetDrag(interaction)

            XCTAssertEqual(changes, [drop, nil])
            XCTAssertFalse(interaction.prepareForDragOperation(sequenceNumber: 43))
        }
    }

    func testExternalDragUpdatesAccessibilityWithoutChangingPressBehavior() throws {
        let drop = try makeDrop(
            pageID: "0123456789abcdef0123456789abcdef",
            sourceLabel: "Roadmap"
        )
        var activationCount = 0
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { .zero },
            onActivate: { activationCount += 1 },
            onDragEnded: { _ in }
        )
        let snapshot = PiPStashHandleDragSnapshot(
            sequenceNumber: 44,
            candidate: drop,
            sourceOperationMask: .copy
        )

        XCTAssertEqual(interaction.draggingEntered(snapshot: snapshot), .copy)
        XCTAssertEqual(interaction.accessibilityLabel(), "Open Roadmap in Perch")
        XCTAssertTrue(interaction.accessibilityPerformPress())
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(
            interaction.accessibilityCustomActions()?.map(\.name),
            ["Show recent PiP pages"]
        )

        interaction.draggingExited()

        XCTAssertEqual(interaction.accessibilityLabel(), "Restore Perch")
        XCTAssertEqual(
            interaction.accessibilityHelp(),
            "Bring the stashed Perch back from the side."
        )
    }

    func testSmallPointerMovementRemainsARestoreClick() throws {
        let pointer = PointerLocation(CGPoint(x: 10, y: 10))
        var activationCount = 0
        var completedFrames: [CGRect] = []
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { pointer.value },
            onActivate: { activationCount += 1 },
            onDragEnded: { completedFrames.append($0) }
        )
        let window = makeWindow(contentView: interaction)
        let originalFrame = window.frame

        interaction.mouseDown(with: try mouseEvent(.leftMouseDown))
        pointer.value = CGPoint(x: 11, y: 11)
        interaction.mouseDragged(with: try mouseEvent(.leftMouseDragged))
        interaction.mouseUp(with: try mouseEvent(.leftMouseUp))

        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(completedFrames.isEmpty)
        XCTAssertEqual(window.frame, originalFrame)
    }

    func testDragMovesPanelAndCompletesWithoutRestoring() throws {
        let pointer = PointerLocation(CGPoint(x: 10, y: 10))
        var activationCount = 0
        var completedFrames: [CGRect] = []
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { pointer.value },
            onActivate: { activationCount += 1 },
            onDragEnded: { completedFrames.append($0) }
        )
        let window = makeWindow(contentView: interaction)

        interaction.mouseDown(with: try mouseEvent(.leftMouseDown))
        pointer.value = CGPoint(x: 50, y: 70)
        interaction.mouseDragged(with: try mouseEvent(.leftMouseDragged))
        interaction.mouseUp(with: try mouseEvent(.leftMouseUp))

        XCTAssertEqual(window.frame.origin, CGPoint(x: 140, y: 160))
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(completedFrames, [window.frame])
    }

    func testInwardDragScrubsRevealWithoutRepositionCompletionOrClick() throws {
        let pointer = PointerLocation(CGPoint(x: 100, y: 10))
        var activationCount = 0
        var completedFrames: [CGRect] = []
        var revealDistances: [CGFloat] = []
        var endedDistances: [CGFloat] = []
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { pointer.value },
            side: .right,
            onActivate: { activationCount += 1 },
            onDragEnded: { completedFrames.append($0) },
            onPullRevealChanged: { revealDistances.append($0) },
            onPullRevealEnded: {
                endedDistances.append($0)
                return true
            }
        )
        let window = makeWindow(contentView: interaction)

        interaction.mouseDown(with: try mouseEvent(.leftMouseDown))
        pointer.value = CGPoint(x: 20, y: 12)
        interaction.mouseDragged(with: try mouseEvent(.leftMouseDragged))
        interaction.mouseUp(with: try mouseEvent(.leftMouseUp))

        XCTAssertEqual(window.frame.origin, CGPoint(x: 20, y: 100))
        XCTAssertEqual(revealDistances, [80])
        XCTAssertEqual(endedDistances, [80])
        XCTAssertEqual(activationCount, 0)
        XCTAssertTrue(completedFrames.isEmpty)
    }

    func testAccessibilityPressRestoresWithoutDragging() {
        var activationCount = 0
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { .zero },
            onActivate: { activationCount += 1 },
            onDragEnded: { _ in }
        )

        XCTAssertTrue(interaction.accessibilityPerformPress())
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(interaction.accessibilityRole(), .button)
        XCTAssertEqual(interaction.accessibilityLabel(), "Restore Perch")
        XCTAssertEqual(
            interaction.accessibilityCustomActions()?.map(\.name),
            ["Show recent PiP pages"]
        )
    }

    func testHoverAndSecondaryClickReportRecentPagesIntentWithoutRestoring() throws {
        var hoverStates: [Bool] = []
        var showRecentCount = 0
        var activationCount = 0
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { .zero },
            onActivate: { activationCount += 1 },
            onDragEnded: { _ in },
            onHoverChanged: { hoverStates.append($0) },
            onShowRecentPages: { showRecentCount += 1 }
        )

        interaction.mouseEntered(with: try trackingEvent(.mouseEntered))
        interaction.mouseExited(with: try trackingEvent(.mouseExited))
        interaction.rightMouseUp(with: try mouseEvent(.rightMouseUp))

        XCTAssertEqual(hoverStates, [true, false])
        XCTAssertEqual(showRecentCount, 1)
        XCTAssertEqual(activationCount, 0)
    }

    func testCrossingDragThresholdEndsHoverAndPreservesDragCompletion() throws {
        let pointer = PointerLocation(CGPoint(x: 10, y: 10))
        var hoverStates: [Bool] = []
        var showRecentCount = 0
        var dragStartCount = 0
        var completedFrames: [CGRect] = []
        let interaction = PiPStashHandleInteractionView(
            pointerLocation: { pointer.value },
            onActivate: {},
            onDragEnded: { completedFrames.append($0) },
            onDragStarted: { dragStartCount += 1 },
            onHoverChanged: { hoverStates.append($0) },
            onShowRecentPages: { showRecentCount += 1 }
        )
        let window = makeWindow(contentView: interaction)

        interaction.mouseDown(with: try mouseEvent(.leftMouseDown))
        pointer.value = CGPoint(x: 14, y: 10)
        interaction.mouseDragged(with: try mouseEvent(.leftMouseDragged))
        interaction.mouseUp(with: try mouseEvent(.leftMouseUp))

        XCTAssertEqual(hoverStates, [false])
        XCTAssertEqual(showRecentCount, 0)
        XCTAssertEqual(dragStartCount, 1)
        XCTAssertEqual(completedFrames, [window.frame])
    }

    private func makeWindow(contentView: NSView) -> NSPanel {
        let window = NSPanel(
            contentRect: CGRect(x: 100, y: 100, width: 36, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        return window
    }

    private func mouseEvent(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func trackingEvent(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.enterExitEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            )
        )
    }

    private func makeDrop(pageID: String, sourceLabel: String?) throws -> NotionPageDrop {
        try NotionPageDrop(
            validating: try XCTUnwrap(URL(string: "https://www.notion.so/Page-\(pageID)")),
            sourceLabel: sourceLabel
        )
    }
}

@MainActor
private final class PointerLocation {
    var value: CGPoint

    init(_ value: CGPoint) {
        self.value = value
    }
}

@MainActor
private final class DropCandidate {
    var value: NotionPageDrop?

    init(_ value: NotionPageDrop?) {
        self.value = value
    }
}
