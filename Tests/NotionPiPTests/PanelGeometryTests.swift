import CoreGraphics
import XCTest

@testable import NotionPiP

final class PanelGeometryTests: XCTestCase {
    func testTopologyCaptureRecordsDisplayAffinity() throws {
        let topology = makeTopology(secondaryID: 22, secondaryX: 1_440)
        let frame = CGRect(x: 2_856, y: 431, width: 480, height: 600)

        let geometry = try XCTUnwrap(
            PanelGeometryPolicy.capture(
                frame: frame,
                topology: topology,
                contentRectForFrameRect: { $0 }
            )
        )

        XCTAssertEqual(geometry.displayAffinity?.identifier, 22)
        XCTAssertEqual(geometry.displayAffinity?.placement, .right)
        XCTAssertFalse(geometry.displayAffinity?.isPrimary ?? true)
    }

    func testTopologyResolutionFollowsSameDisplayAfterRearrangement() throws {
        let original = makeTopology(secondaryID: 22, secondaryX: 1_440)
        let geometry = try XCTUnwrap(
            PanelGeometryPolicy.capture(
                frame: CGRect(x: 2_856, y: 431, width: 480, height: 600),
                topology: original,
                contentRectForFrameRect: { $0 }
            )
        )
        let rearranged = makeTopology(secondaryID: 22, secondaryX: -1_920)

        let resolved = PanelGeometryPolicy.resolvedFrame(
            for: geometry,
            topology: rearranged,
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(resolved, CGRect(x: -504, y: 431, width: 480, height: 600))
    }

    func testTopologyResolutionUsesStrongChangedIdentifierAndScaleReplacement() throws {
        let original = makeTopology(secondaryID: 22, secondaryX: 1_440)
        let geometry = try XCTUnwrap(
            PanelGeometryPolicy.capture(
                frame: CGRect(x: 2_856, y: 431, width: 480, height: 600),
                topology: original,
                contentRectForFrameRect: { $0 }
            )
        )
        let replacement = makeTopology(
            secondaryID: 77,
            secondaryX: -1_706,
            secondaryWidth: 1_706,
            secondaryHeight: 960,
            secondaryScale: 2
        )

        let resolved = PanelGeometryPolicy.resolvedFrame(
            for: geometry,
            topology: replacement,
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(resolved, CGRect(x: -504, y: 311, width: 480, height: 600))
    }

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

    private func makeTopology(
        secondaryID: UInt32,
        secondaryX: CGFloat,
        secondaryWidth: CGFloat = 1_920,
        secondaryHeight: CGFloat = 1_080,
        secondaryScale: CGFloat = 1
    ) -> DisplayTopology {
        DisplayTopology(
            revision: 1,
            displays: [
                DisplayDescriptor(
                    identifier: 11,
                    frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
                    backingScaleFactor: 2,
                    isPrimary: true
                ),
                DisplayDescriptor(
                    identifier: secondaryID,
                    frame: CGRect(
                        x: secondaryX,
                        y: 0,
                        width: secondaryWidth,
                        height: secondaryHeight
                    ),
                    visibleFrame: CGRect(
                        x: secondaryX,
                        y: 0,
                        width: secondaryWidth,
                        height: secondaryHeight - 25
                    ),
                    backingScaleFactor: secondaryScale,
                    isPrimary: false
                ),
            ]
        )
    }
}
