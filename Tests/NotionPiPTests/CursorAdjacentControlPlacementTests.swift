import CoreGraphics
import XCTest
@testable import NotionPiP

final class CursorAdjacentControlPlacementTests: XCTestCase {
    func testPlacesControlBelowAndRightOfCaret() {
        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: geometry(left: 100, top: 40, bottom: 60),
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 121, y: 81)
        )
    }

    func testFlipsControlToLeftAtRightEdge() {
        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: geometry(left: 390, top: 40, bottom: 60),
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 369, y: 81)
        )
    }

    func testFlipsControlAboveCaretAtBottomEdge() {
        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: geometry(left: 100, top: 280, bottom: 300),
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 121, y: 259)
        )
    }

    func testClampsControlInsideBothEdges() {
        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: geometry(left: -100, top: -100, bottom: -80),
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 23, y: 23)
        )
        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: geometry(left: 500, top: 400, bottom: 420),
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 377, y: 277)
        )
    }

    func testScalesCSSViewportCoordinatesToViewPoints() {
        let geometry = NotionEditorCaretGeometry(
            left: 200,
            top: 100,
            bottom: 140,
            viewportWidth: 800,
            viewportHeight: 600
        )

        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: geometry,
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 121, y: 91)
        )
    }

    func testUsesBottomRightFallbackWithoutCaretGeometry() {
        XCTAssertEqual(
            CursorAdjacentControlPlacement.center(
                for: nil,
                in: CGSize(width: 400, height: 300)
            ),
            CGPoint(x: 377, y: 277)
        )
    }

    private func geometry(
        left: Double,
        top: Double,
        bottom: Double
    ) -> NotionEditorCaretGeometry {
        NotionEditorCaretGeometry(
            left: left,
            top: top,
            bottom: bottom,
            viewportWidth: 400,
            viewportHeight: 300
        )
    }
}
