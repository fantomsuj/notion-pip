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
}
