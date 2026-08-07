import CoreGraphics
import XCTest
@testable import NotionPiP

final class PanelStashPolicyTests: XCTestCase {
    func testIntentRemapsSideAndVerticalPositionAfterDisplayRearrangement() throws {
        let original = makeTopology(secondaryID: 22, secondaryX: 1_440)
        let placement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 3_324, y: 300, width: 36, height: 96)
        )
        let intent = try XCTUnwrap(
            PanelStashPolicy.intent(for: placement, topology: original)
        )
        let rearranged = makeTopology(secondaryID: 22, secondaryX: -1_920)

        let remapped = PanelStashPolicy.placement(
            for: intent,
            currentFrame: placement.frame,
            topology: rearranged
        )

        XCTAssertEqual(remapped?.side, .right)
        XCTAssertEqual(remapped?.frame.minX, -36)
        XCTAssertEqual(remapped?.frame.minY, 300)
    }

    func testIntentUsesChangedIdentifierAndScaleReplacement() throws {
        let original = makeTopology(secondaryID: 22, secondaryX: 1_440)
        let placement = PanelStashPlacement(
            side: .left,
            frame: CGRect(x: 1_440, y: 600, width: 36, height: 96)
        )
        let intent = try XCTUnwrap(
            PanelStashPolicy.intent(for: placement, topology: original)
        )
        let replacement = makeTopology(
            secondaryID: 77,
            secondaryX: -1_706,
            width: 1_706,
            height: 960,
            scale: 2
        )

        let remapped = PanelStashPolicy.placement(
            for: intent,
            currentFrame: placement.frame,
            topology: replacement
        )

        XCTAssertEqual(remapped?.side, .left)
        XCTAssertEqual(remapped?.frame.minX, -1_706)
        XCTAssertGreaterThanOrEqual(remapped?.frame.minY ?? -.infinity, 0)
        XCTAssertLessThanOrEqual(remapped?.frame.maxY ?? .infinity, 935)
    }

    func testIntentPlacementUsesVisibleFrameToAvoidSystemUI() {
        let display = DisplayDescriptor(
            identifier: 11,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 900),
            visibleFrame: CGRect(x: 80, y: 50, width: 920, height: 825),
            backingScaleFactor: 2,
            isPrimary: true
        )
        let topology = DisplayTopology(revision: 1, displays: [display])
        let intent = PanelStashIntent(
            side: .left,
            verticalFraction: 1,
            displayAffinity: display.affinity(in: topology)
        )

        let placement = PanelStashPolicy.placement(
            for: intent,
            currentFrame: CGRect(x: 0, y: 900, width: 36, height: 96),
            topology: topology
        )

        XCTAssertEqual(placement?.frame, CGRect(x: 80, y: 779, width: 36, height: 96))
    }

    func testPlacementUsesLeftEdgeWhenPanelIsOnLeftHalfOfScreen() throws {
        let panel = CGRect(x: 80, y: 220, width: 400, height: 360)
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let placement = try XCTUnwrap(
            PanelStashPolicy.placement(for: panel, visibleFrames: [screen])
        )

        XCTAssertEqual(placement.side, .left)
        XCTAssertEqual(placement.frame, CGRect(x: 0, y: 352, width: 36, height: 96))
    }

    func testPlacementUsesRightEdgeWhenPanelIsOnRightHalfOfScreen() throws {
        let panel = CGRect(x: 620, y: 100, width: 300, height: 400)
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let placement = try XCTUnwrap(
            PanelStashPolicy.placement(for: panel, visibleFrames: [screen])
        )

        XCTAssertEqual(placement.side, .right)
        XCTAssertEqual(placement.frame, CGRect(x: 964, y: 252, width: 36, height: 96))
    }

    func testPlacementUsesScreenWithGreatestPanelIntersection() throws {
        let panel = CGRect(x: 1_350, y: 200, width: 500, height: 400)
        let screens = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
        ]

        let placement = try XCTUnwrap(
            PanelStashPolicy.placement(for: panel, visibleFrames: screens)
        )

        XCTAssertEqual(placement.side, .left)
        XCTAssertEqual(placement.frame, CGRect(x: 1_440, y: 352, width: 36, height: 96))
    }

    func testPlacementClampsHandleInsideVisibleFrameVertically() throws {
        let panel = CGRect(x: 700, y: 740, width: 240, height: 160)
        let screen = CGRect(x: 0, y: 20, width: 1_000, height: 780)

        let placement = try XCTUnwrap(
            PanelStashPolicy.placement(for: panel, visibleFrames: [screen])
        )

        XCTAssertEqual(placement.frame, CGRect(x: 964, y: 704, width: 36, height: 96))
    }

    func testPlacementWithoutVisibleScreensReturnsNil() {
        XCTAssertNil(
            PanelStashPolicy.placement(
                for: CGRect(x: 80, y: 220, width: 400, height: 360),
                visibleFrames: []
            )
        )
    }

    func testDraggedPlacementSnapsToNearestEdgeAndPreservesVerticalOrigin() throws {
        let placement = try XCTUnwrap(
            PanelStashPolicy.snappedPlacement(
                for: CGRect(x: 120, y: 210, width: 36, height: 96),
                visibleFrames: [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
            )
        )

        XCTAssertEqual(
            placement,
            PanelStashPlacement(
                side: .left,
                frame: CGRect(x: 0, y: 210, width: 36, height: 96)
            )
        )
    }

    func testDraggedPlacementSnapsToRightAndClampsAboveVisibleFrame() throws {
        let placement = try XCTUnwrap(
            PanelStashPolicy.snappedPlacement(
                for: CGRect(x: 900, y: 780, width: 36, height: 96),
                visibleFrames: [CGRect(x: 0, y: 20, width: 1_000, height: 780)]
            )
        )

        XCTAssertEqual(
            placement,
            PanelStashPlacement(
                side: .right,
                frame: CGRect(x: 964, y: 704, width: 36, height: 96)
            )
        )
    }

    func testDraggedPlacementUsesDisplayContainingMostOfHandle() throws {
        let placement = try XCTUnwrap(
            PanelStashPolicy.snappedPlacement(
                for: CGRect(x: 1_430, y: 310, width: 36, height: 96),
                visibleFrames: [
                    CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    CGRect(x: 1_440, y: 100, width: 1_920, height: 1_080),
                ]
            )
        )

        XCTAssertEqual(
            placement,
            PanelStashPlacement(
                side: .left,
                frame: CGRect(x: 1_440, y: 310, width: 36, height: 96)
            )
        )
    }

    func testDraggedPlacementWithoutVisibleScreensReturnsNil() {
        XCTAssertNil(
            PanelStashPolicy.snappedPlacement(
                for: CGRect(x: 120, y: 210, width: 36, height: 96),
                visibleFrames: []
            )
        )
    }

    private func makeTopology(
        secondaryID: UInt32,
        secondaryX: CGFloat,
        width: CGFloat = 1_920,
        height: CGFloat = 1_080,
        scale: CGFloat = 1
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
                    frame: CGRect(x: secondaryX, y: 0, width: width, height: height),
                    visibleFrame: CGRect(x: secondaryX, y: 0, width: width, height: height - 25),
                    backingScaleFactor: scale,
                    isPrimary: false
                ),
            ]
        )
    }
}
