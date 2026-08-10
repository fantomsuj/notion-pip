import AppKit
import XCTest
@testable import NotionPiP

@MainActor
final class PiPStashHandleInteractionTests: XCTestCase {
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
        XCTAssertEqual(interaction.accessibilityLabel(), "Restore Notion PiP")
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
}

@MainActor
private final class PointerLocation {
    var value: CGPoint

    init(_ value: CGPoint) {
        self.value = value
    }
}
