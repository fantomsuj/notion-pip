import CoreGraphics
import XCTest
@testable import Perch

final class PanelStashShelfPolicyTests: XCTestCase {
    func testRightEdgeShelfExtendsInwardWithoutMovingHandle() throws {
        let placement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 352, width: 36, height: 96)
        )

        let frame = try XCTUnwrap(
            PanelStashShelfPolicy.frame(
                attachedTo: placement,
                itemCount: 5,
                visibleFrames: [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
            )
        )

        XCTAssertEqual(frame.maxX, placement.frame.minX - PanelStashShelfPolicy.edgeGap)
        XCTAssertGreaterThanOrEqual(frame.minY, 20)
        XCTAssertLessThanOrEqual(frame.maxY, 800)
        XCTAssertEqual(placement.frame, CGRect(x: 964, y: 352, width: 36, height: 96))
    }

    func testLeftEdgeShelfExtendsInward() throws {
        let placement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 0, y: 352, width: 36, height: 96)
        )

        let frame = try XCTUnwrap(
            PanelStashShelfPolicy.frame(
                attachedTo: placement,
                itemCount: 3,
                visibleFrames: [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
            )
        )

        XCTAssertEqual(frame.minX, placement.frame.maxX + PanelStashShelfPolicy.edgeGap)
    }

    func testShelfClampsAtTopAndBottom() throws {
        let screen = CGRect(x: 0, y: 20, width: 1_000, height: 780)
        let top = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 704, width: 36, height: 96)
        )
        let bottom = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 20, width: 36, height: 96)
        )

        XCTAssertEqual(
            try XCTUnwrap(PanelStashShelfPolicy.frame(
                attachedTo: top,
                itemCount: 5,
                visibleFrames: [screen]
            )).maxY,
            screen.maxY
        )
        XCTAssertEqual(
            try XCTUnwrap(PanelStashShelfPolicy.frame(
                attachedTo: bottom,
                itemCount: 5,
                visibleFrames: [screen]
            )).minY,
            screen.minY
        )
    }

    func testShelfFitsShortDisplay() throws {
        let screen = CGRect(x: 0, y: 20, width: 500, height: 180)
        let placement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 464, y: 62, width: 36, height: 96)
        )

        let frame = try XCTUnwrap(PanelStashShelfPolicy.frame(
            attachedTo: placement,
            itemCount: 5,
            visibleFrames: [screen]
        ))

        XCTAssertEqual(frame.height, screen.height)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
    }

    func testShelfSizeClampsRowCount() {
        XCTAssertEqual(PanelStashShelfPolicy.size(itemCount: 0).width, 300)
        XCTAssertEqual(
            PanelStashShelfPolicy.size(itemCount: 99).height,
            PanelStashShelfPolicy.headerHeight
                + CGFloat(PiPRecentPagesSnapshot.maximumItems) * PanelStashShelfPolicy.rowHeight
                + PanelStashShelfPolicy.verticalPadding * 2
        )
    }

    func testShelfReturnsNilWithoutRowsOrAvailableDisplay() {
        let placement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 964, y: 352, width: 36, height: 96)
        )

        XCTAssertNil(PanelStashShelfPolicy.frame(
            attachedTo: placement,
            itemCount: 0,
            visibleFrames: [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
        ))
        XCTAssertNil(PanelStashShelfPolicy.frame(
            attachedTo: placement,
            itemCount: 2,
            visibleFrames: []
        ))
    }
}
