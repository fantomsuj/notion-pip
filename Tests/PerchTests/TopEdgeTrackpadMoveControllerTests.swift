import AppKit
import CoreGraphics
import XCTest
@testable import Perch

@MainActor
final class TopEdgeTrackpadMoveControllerTests: XCTestCase {
    private let contentBounds = CGRect(x: 0, y: 0, width: 480, height: 720)
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    func testAppKitGesturePhasesMapToPolicyPhases() {
        XCTAssertEqual(TopEdgeTrackpadMovePhase(appKitPhase: .began), .began)
        XCTAssertEqual(TopEdgeTrackpadMovePhase(appKitPhase: .changed), .changed)
        XCTAssertEqual(TopEdgeTrackpadMovePhase(appKitPhase: .stationary), .stationary)
        XCTAssertEqual(TopEdgeTrackpadMovePhase(appKitPhase: .ended), .ended)
        XCTAssertEqual(TopEdgeTrackpadMovePhase(appKitPhase: .cancelled), .cancelled)
        XCTAssertEqual(
            TopEdgeTrackpadMovePhase(appKitPhase: NSEvent.Phase(rawValue: 0)),
            .none
        )
    }

    func testPreciseGestureBeginsInsideHiddenRevealStrip() {
        let controller = TopEdgeTrackpadMoveController()

        let decision = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 12, height: -9)
            )
        )

        XCTAssertEqual(
            decision,
            .move(
                translation: CGSize(width: 12, height: -9),
                visibleFrame: visibleFrame
            )
        )
    }

    func testPreciseGestureUsesMinimumYAsTopForFlippedSwiftUIContent() {
        let controller = TopEdgeTrackpadMoveController()

        let accepted = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 8),
                isContentFlipped: true,
                translation: CGSize(width: 12, height: -9)
            )
        )
        _ = controller.handle(
            input(
                phase: .ended,
                location: CGPoint(x: 240, y: 8),
                isContentFlipped: true,
                translation: .zero
            )
        )
        let lowerBoundary = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 36),
                isContentFlipped: true,
                translation: CGSize(width: 0, height: 8)
            )
        )

        XCTAssertEqual(
            accepted,
            .move(
                translation: CGSize(width: 12, height: -9),
                visibleFrame: visibleFrame
            )
        )
        XCTAssertEqual(lowerBoundary, .forward)
    }

    func testPreciseGestureBeginsElsewhereInsideVisibleToolbar() {
        let controller = TopEdgeTrackpadMoveController()

        let decision = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 120, y: 690),
                translation: CGSize(width: -4, height: 7)
            )
        )

        XCTAssertEqual(
            decision,
            .move(
                translation: CGSize(width: -4, height: 7),
                visibleFrame: visibleFrame
            )
        )
    }

    func testGestureAtExactLowerToolbarBoundaryIsForwardedToContent() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .began,
                    location: CGPoint(x: 240, y: 684),
                    translation: CGSize(width: 0, height: 8)
                )
            ),
            .forward
        )
    }

    func testOrdinaryNotionScrollIsForwarded() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .began,
                    location: CGPoint(x: 240, y: 400),
                    translation: CGSize(width: 0, height: 8)
                )
            ),
            .forward
        )
    }

    func testImpreciseMouseWheelEventIsForwarded() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .began,
                    location: CGPoint(x: 240, y: 712),
                    hasPreciseScrollingDeltas: false,
                    translation: CGSize(width: 0, height: 8)
                )
            ),
            .forward
        )
    }

    func testExpandedPanelGestureIsForwarded() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .began,
                    location: CGPoint(x: 240, y: 712),
                    isExpanded: true,
                    translation: CGSize(width: 0, height: 8)
                )
            ),
            .forward
        )
    }

    func testGestureWithoutResolvedDisplayIsForwarded() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .began,
                    location: CGPoint(x: 240, y: 712),
                    visibleFrame: nil,
                    translation: CGSize(width: 0, height: 8)
                )
            ),
            .forward
        )
    }

    func testAcceptedGestureRemainsLatchedAfterLocalPointerLeavesToolbar() {
        let controller = TopEdgeTrackpadMoveController()
        _ = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 1, height: 2)
            )
        )

        let changed = controller.handle(
            input(
                phase: .changed,
                location: CGPoint(x: 240, y: 200),
                visibleFrame: nil,
                translation: CGSize(width: 6, height: -5)
            )
        )
        let ended = controller.handle(
            input(
                phase: .ended,
                location: CGPoint(x: 240, y: 200),
                visibleFrame: nil,
                translation: .zero
            )
        )

        XCTAssertEqual(
            changed,
            .move(
                translation: CGSize(width: 6, height: -5),
                visibleFrame: visibleFrame
            )
        )
        XCTAssertEqual(ended, .consume)
    }

    func testZeroDeltaEventIsConsumedWithoutMovingActiveGesture() {
        let controller = TopEdgeTrackpadMoveController()
        _ = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 1, height: 2)
            )
        )

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .changed,
                    location: CGPoint(x: 240, y: 712),
                    translation: .zero
                )
            ),
            .consume
        )
    }

    func testStationaryPhysicalEventIsConsumedWhileGestureIsActive() {
        let controller = TopEdgeTrackpadMoveController()
        _ = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 1, height: 2)
            )
        )

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .stationary,
                    location: CGPoint(x: 240, y: 712),
                    translation: .zero
                )
            ),
            .consume
        )
    }

    func testStationaryMomentumIsSuppressedAfterAcceptedGesture() {
        let controller = TopEdgeTrackpadMoveController()
        _ = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 1, height: 2)
            )
        )
        _ = controller.handle(
            input(
                phase: .ended,
                location: CGPoint(x: 240, y: 712),
                translation: .zero
            )
        )

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .none,
                    momentumPhase: .stationary,
                    location: CGPoint(x: 240, y: 400),
                    translation: CGSize(width: 30, height: -40)
                )
            ),
            .consume
        )
    }

    func testUnrelatedStationaryEventIsForwarded() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .stationary,
                    location: CGPoint(x: 240, y: 400),
                    translation: .zero
                )
            ),
            .forward
        )
    }

    func testResetClearsAnInterruptedGesture() {
        let controller = TopEdgeTrackpadMoveController()
        _ = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 1, height: 2)
            )
        )

        controller.reset()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .stationary,
                    location: CGPoint(x: 240, y: 712),
                    translation: .zero
                )
            ),
            .forward
        )
    }

    func testMomentumIsConsumedWithoutMovingAndResetsAfterCompletion() {
        let controller = TopEdgeTrackpadMoveController()
        _ = controller.handle(
            input(
                phase: .began,
                location: CGPoint(x: 240, y: 712),
                translation: CGSize(width: 1, height: 2)
            )
        )
        _ = controller.handle(
            input(
                phase: .ended,
                location: CGPoint(x: 240, y: 712),
                translation: .zero
            )
        )

        for momentumPhase in [
            TopEdgeTrackpadMovePhase.began,
            .changed,
            .ended,
        ] {
            XCTAssertEqual(
                controller.handle(
                    input(
                        phase: .none,
                        momentumPhase: momentumPhase,
                        location: CGPoint(x: 240, y: 400),
                        translation: CGSize(width: 30, height: -40)
                    )
                ),
                .consume
            )
        }

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .began,
                    location: CGPoint(x: 240, y: 400),
                    translation: CGSize(width: 0, height: 5)
                )
            ),
            .forward
        )
    }

    func testUnrelatedMomentumWithoutAcceptedGestureIsForwarded() {
        let controller = TopEdgeTrackpadMoveController()

        XCTAssertEqual(
            controller.handle(
                input(
                    phase: .none,
                    momentumPhase: .began,
                    location: CGPoint(x: 240, y: 400),
                    translation: CGSize(width: 0, height: 5)
                )
            ),
            .forward
        )
    }

    private func input(
        phase: TopEdgeTrackpadMovePhase,
        momentumPhase: TopEdgeTrackpadMovePhase = .none,
        location: CGPoint,
        isContentFlipped: Bool = false,
        hasPreciseScrollingDeltas: Bool = true,
        isExpanded: Bool = false,
        visibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1_440, height: 900),
        translation: CGSize
    ) -> TopEdgeTrackpadMoveInput {
        TopEdgeTrackpadMoveInput(
            phase: phase,
            momentumPhase: momentumPhase,
            hasPreciseScrollingDeltas: hasPreciseScrollingDeltas,
            locationInContent: location,
            contentBounds: contentBounds,
            isContentFlipped: isContentFlipped,
            isExpanded: isExpanded,
            visibleFrame: visibleFrame,
            translation: translation
        )
    }
}
