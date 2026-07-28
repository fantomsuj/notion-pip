import CoreGraphics
import XCTest

@testable import NotionPiP

final class PanelFramePolicyTests: XCTestCase {
    func testOffscreenFrameIsClampedInsideAvailableScreen() {
        let restoredFrame = CGRect(x: 1_800, y: 1_200, width: 320, height: 240)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let clamped = PanelFramePolicy.clamped(restoredFrame, visibleFrames: [visibleFrame])

        XCTAssertEqual(clamped, CGRect(x: 680, y: 560, width: 320, height: 240))
    }

    func testClampUsesIntersectingScreenAndPreservesFrameSize() {
        let restoredFrame = CGRect(x: 1_850, y: 200, width: 400, height: 300)
        let screens = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
        ]

        let clamped = PanelFramePolicy.clamped(restoredFrame, visibleFrames: screens)

        XCTAssertEqual(clamped, restoredFrame)
    }

    func testClampWithoutVisibleScreensLeavesFrameUnchanged() {
        let restoredFrame = CGRect(x: 12, y: 34, width: 500, height: 600)

        XCTAssertEqual(PanelFramePolicy.clamped(restoredFrame, visibleFrames: []), restoredFrame)
    }

    func testInitialFrameUsesSecondaryDisplayContainingPointer() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
            ),
            ScreenGeometry(
                frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_055)
            ),
        ]

        let frame = PanelFramePolicy.initialFrame(
            size: CGSize(width: 520, height: 680),
            minimumSize: CGSize(width: 360, height: 420),
            pointerLocation: CGPoint(x: 2_000, y: 500),
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: 2_816, y: 351, width: 520, height: 680))
    }

    func testInitialFrameSupportsPointerOnDisplayWithNegativeOrigin() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
            ),
            ScreenGeometry(
                frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
            ),
        ]

        let frame = PanelFramePolicy.initialFrame(
            size: CGSize(width: 520, height: 680),
            minimumSize: CGSize(width: 360, height: 420),
            pointerLocation: CGPoint(x: -100, y: 500),
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: -544, y: 351, width: 520, height: 680))
    }

    func testInitialFrameUsesFullFrameToRecognizePointerInMenuBar() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
            ),
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
            ),
        ]

        let frame = PanelFramePolicy.initialFrame(
            size: CGSize(width: 520, height: 680),
            minimumSize: CGSize(width: 360, height: 420),
            pointerLocation: CGPoint(x: 500, y: 890),
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: 896, y: 171, width: 520, height: 680))
    }

    func testInitialFrameFallsBackToFirstScreenDeterministically() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055)
            ),
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
            ),
        ]

        let frame = PanelFramePolicy.initialFrame(
            size: CGSize(width: 520, height: 680),
            minimumSize: CGSize(width: 360, height: 420),
            pointerLocation: CGPoint(x: 5_000, y: 5_000),
            screens: screens
        )

        XCTAssertEqual(frame, CGRect(x: -544, y: 351, width: 520, height: 680))
    }

    func testInitialFrameWithoutScreensReturnsNil() {
        XCTAssertNil(
            PanelFramePolicy.initialFrame(
                size: CGSize(width: 520, height: 680),
                minimumSize: CGSize(width: 360, height: 420),
                pointerLocation: CGPoint(x: 100, y: 100),
                screens: []
            )
        )
    }

    func testClampExpandsUndersizedLegacyFrameBeforeConstrainingOrigin() {
        let restoredFrame = CGRect(x: 800, y: 380, width: 200, height: 300)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let clamped = PanelFramePolicy.clamped(
            restoredFrame,
            visibleFrames: [visibleFrame],
            minimumSize: CGSize(width: 360, height: 420)
        )

        XCTAssertEqual(clamped, CGRect(x: 640, y: 380, width: 360, height: 420))
    }

    func testClampCapsMinimumDimensionsToDisplaySize() {
        let restoredFrame = CGRect(x: 100, y: 100, width: 200, height: 300)
        let visibleFrame = CGRect(x: 0, y: 0, width: 300, height: 350)

        let clamped = PanelFramePolicy.clamped(
            restoredFrame,
            visibleFrames: [visibleFrame],
            minimumSize: CGSize(width: 360, height: 420)
        )

        XCTAssertEqual(clamped, visibleFrame)
    }

    func testInitialFrameConvertsAuthoritativeContentSizeBeforePlacement() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 775)
            )
        ]

        let frame = PanelFramePolicy.initialFrame(
            contentSize: CGSize(width: 420, height: 520),
            pointerLocation: CGPoint(x: 500, y: 400),
            screens: screens,
            frameForContentRect: { contentRect in
                CGRect(
                    origin: contentRect.origin,
                    size: CGSize(
                        width: contentRect.width + 12,
                        height: contentRect.height + 40
                    )
                )
            }
        )

        XCTAssertEqual(frame, CGRect(x: 544, y: 191, width: 432, height: 560))
    }

    func testContentAndFrameConversionHelpersUseInjectedWindowConversions() {
        let frameSize = PanelFramePolicy.frameSize(
            forContentSize: CGSize(width: 320, height: 360),
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { contentRect in
                CGRect(
                    x: contentRect.minX - 6,
                    y: contentRect.minY,
                    width: contentRect.width + 12,
                    height: contentRect.height + 38
                )
            }
        )
        let contentSize = PanelFramePolicy.contentSize(
            forFrame: CGRect(x: 40, y: 50, width: 512, height: 638),
            contentRectForFrameRect: { frameRect in
                CGRect(
                    x: frameRect.minX + 6,
                    y: frameRect.minY,
                    width: frameRect.width - 12,
                    height: frameRect.height - 38
                )
            }
        )

        XCTAssertEqual(frameSize, CGSize(width: 372, height: 458))
        XCTAssertEqual(contentSize, CGSize(width: 500, height: 600))
    }

    func testPlacementPreservesNearestScreenEdgesWhenApplyingContentSize() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let currentFrame = CGRect(x: 1_016, y: 251, width: 400, height: 600)

        let placement = PanelFramePolicy.placement(
            preferredContentSize: CGSize(width: 680, height: 720),
            anchoredTo: currentFrame,
            visibleFrames: [screen],
            frameForContentRect: { contentRect in
                CGRect(
                    origin: contentRect.origin,
                    size: CGSize(
                        width: contentRect.width,
                        height: contentRect.height + 32
                    )
                )
            }
        )

        XCTAssertEqual(
            placement.frame,
            CGRect(x: 736, y: 99, width: 680, height: 752)
        )
        XCTAssertEqual(placement.preferredContentSize, CGSize(width: 680, height: 720))
        XCTAssertEqual(
            placement.anchor,
            PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )
    }

    func testOversizedPreferredContentSizeIsRetainedWhileFrameIsClamped() {
        let screen = CGRect(x: 0, y: 0, width: 500, height: 400)
        let currentFrame = CGRect(x: 76, y: 24, width: 400, height: 352)

        let placement = PanelFramePolicy.placement(
            preferredContentSize: CGSize(width: 680, height: 720),
            anchoredTo: currentFrame,
            visibleFrames: [screen],
            frameForContentRect: frameWithTitleBar
        )

        XCTAssertEqual(placement.frame, screen)
        XCTAssertEqual(placement.preferredContentSize, CGSize(width: 680, height: 720))
        XCTAssertEqual(
            placement.anchor,
            PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )
    }

    func testPreservedAnchorRestoresPreferredSizeOnLargerDisplay() throws {
        let smallScreen = CGRect(x: 0, y: 0, width: 500, height: 400)
        let originalFrame = CGRect(x: 76, y: 24, width: 400, height: 352)
        let clamped = PanelFramePolicy.placement(
            preferredContentSize: CGSize(width: 680, height: 720),
            anchoredTo: originalFrame,
            visibleFrames: [smallScreen],
            frameForContentRect: frameWithTitleBar
        )
        let preservedAnchor = try XCTUnwrap(clamped.anchor)

        let restored = PanelFramePolicy.placement(
            preferredContentSize: clamped.preferredContentSize,
            anchoredTo: clamped.frame,
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_440, height: 900)],
            preserving: preservedAnchor,
            frameForContentRect: frameWithTitleBar
        )

        XCTAssertEqual(restored.frame, CGRect(x: 736, y: 124, width: 680, height: 752))
        XCTAssertEqual(restored.preferredContentSize, CGSize(width: 680, height: 720))
        XCTAssertEqual(restored.anchor, preservedAnchor)
    }

    private func frameWithTitleBar(_ contentRect: CGRect) -> CGRect {
        CGRect(
            origin: contentRect.origin,
            size: CGSize(
                width: contentRect.width,
                height: contentRect.height + 32
            )
        )
    }
}
