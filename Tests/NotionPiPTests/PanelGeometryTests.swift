import CoreGraphics
import XCTest

@testable import NotionPiP

final class PanelGeometryTests: XCTestCase {
    func testCaptureRecordsExactHorizontalFrameContentSizeAndNearestEdges() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = CGRect(x: 656, y: 356, width: 760, height: 520)

        let geometry = try XCTUnwrap(
            PanelGeometryPolicy.capture(
                frame: frame,
                visibleFrames: [screen],
                contentRectForFrameRect: { $0 }
            )
        )

        XCTAssertEqual(geometry.desiredContentSize, try PanelContentSize(width: 760, height: 520))
        XCTAssertEqual(geometry.frame, frame)
        XCTAssertEqual(geometry.visibleFrame, screen)
        XCTAssertEqual(
            geometry.anchor,
            PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )
    }

    func testResolutionOnSameDisplayReturnsExactCommittedFrame() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = CGRect(x: 613, y: 219, width: 803, height: 657)
        let geometry = try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 803, height: 657),
            frame: frame,
            visibleFrame: screen,
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )

        let resolved = PanelGeometryPolicy.resolvedFrame(
            for: geometry,
            visibleFrames: [screen],
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(resolved, frame)
    }

    func testResolutionOnReplacementDisplayUsesSavedSizeAndAnchor() throws {
        let originalScreen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let replacementScreen = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let geometry = try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 760, height: 520),
            frame: CGRect(x: 656, y: 356, width: 760, height: 520),
            visibleFrame: originalScreen,
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )

        let resolved = PanelGeometryPolicy.resolvedFrame(
            for: geometry,
            visibleFrames: [replacementScreen],
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(resolved, CGRect(x: 416, y: 256, width: 760, height: 520))
    }

    func testSmallDisplayClampDoesNotReplaceDesiredContentSize() throws {
        let originalScreen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let smallScreen = CGRect(x: 0, y: 0, width: 500, height: 400)
        let geometry = try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 760, height: 520),
            frame: CGRect(x: 656, y: 356, width: 760, height: 520),
            visibleFrame: originalScreen,
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )

        let resolved = PanelGeometryPolicy.resolvedFrame(
            for: geometry,
            visibleFrames: [smallScreen],
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(resolved, smallScreen)
        XCTAssertEqual(geometry.desiredContentSize, try PanelContentSize(width: 760, height: 520))
    }
}
