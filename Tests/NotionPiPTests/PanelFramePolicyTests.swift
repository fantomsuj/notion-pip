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
}
