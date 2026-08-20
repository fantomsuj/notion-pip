import CoreGraphics
import XCTest
@testable import Perch

final class StashHandleDropTargetPolicyTests: XCTestCase {
    func testLeftPlacementRetainsItsMinimumX() throws {
        let placement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 100, y: 300, width: 36, height: 96)
        )

        let frame = try XCTUnwrap(
            StashHandleDropTargetPolicy.expandedFrame(
                for: placement,
                visibleFrames: [CGRect(x: 100, y: 50, width: 1_000, height: 700)]
            )
        )

        XCTAssertEqual(frame.minX, 100)
        XCTAssertEqual(frame.width, 260)
    }

    func testRightPlacementRetainsItsMaximumX() throws {
        let placement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 1_064, y: 300, width: 36, height: 96)
        )

        let frame = try XCTUnwrap(
            StashHandleDropTargetPolicy.expandedFrame(
                for: placement,
                visibleFrames: [CGRect(x: 100, y: 50, width: 1_000, height: 700)]
            )
        )

        XCTAssertEqual(frame.maxX, 1_100)
        XCTAssertEqual(frame.width, 260)
    }

    func testExpansionPreservesPlacementVerticalOriginAndHeight() throws {
        let placement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 100, y: 327, width: 36, height: 96)
        )

        let frame = try XCTUnwrap(
            StashHandleDropTargetPolicy.expandedFrame(
                for: placement,
                visibleFrames: [CGRect(x: 100, y: 50, width: 1_000, height: 700)]
            )
        )

        XCTAssertEqual(frame.minY, 327)
        XCTAssertEqual(frame.height, 96)
    }

    func testExpansionClampsWidthToNarrowVisibleFrame() throws {
        let placement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 144, y: 80, width: 36, height: 96)
        )
        let visibleFrame = CGRect(x: 0, y: 50, width: 180, height: 300)

        let frame = try XCTUnwrap(
            StashHandleDropTargetPolicy.expandedFrame(
                for: placement,
                visibleFrames: [visibleFrame]
            )
        )

        XCTAssertEqual(frame.width, 180)
        XCTAssertEqual(frame, CGRect(x: 0, y: 80, width: 180, height: 96))
        XCTAssertEqual(frame.maxX, visibleFrame.maxX)
    }

    func testExpansionReturnsNilWithoutMatchingVisibleDisplay() {
        let placement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 100, y: 300, width: 36, height: 96)
        )

        XCTAssertNil(
            StashHandleDropTargetPolicy.expandedFrame(
                for: placement,
                visibleFrames: []
            )
        )
    }
}
