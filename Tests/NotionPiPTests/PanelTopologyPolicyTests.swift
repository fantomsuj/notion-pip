import CoreGraphics
import XCTest

@testable import NotionPiP

final class PanelTopologyPolicyTests: XCTestCase {
    func testVisibleDisconnectClampsEffectiveFrameWithoutChangingCommittedGeometry() throws {
        let geometry = try makeSecondaryGeometry()
        let fallback = DisplayTopology(revision: 2, displays: [primary(width: 500, height: 400)])

        let decision = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: geometry.frame,
            presentation: .visible,
            lastAcceptedRevision: 1,
            topology: fallback,
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(decision?.acceptedRevision, 2)
        XCTAssertEqual(decision?.panelFrame, CGRect(x: 0, y: 0, width: 500, height: 375))
        XCTAssertEqual(decision?.panelFrameShouldDisplay, true)
        XCTAssertNil(decision?.stashPlacement)
        XCTAssertEqual(geometry.desiredContentSize.cgSize, CGSize(width: 680, height: 720))
    }

    func testReconnectRestoresPreferredSizeAndEdgeIntent() throws {
        let geometry = try makeSecondaryGeometry()
        let reconnected = topology(revision: 3)

        let decision = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: CGRect(x: 0, y: 0, width: 500, height: 375),
            presentation: .visible,
            lastAcceptedRevision: 2,
            topology: reconnected,
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(decision?.panelFrame, geometry.frame)
        XCTAssertEqual(decision?.panelFrameShouldDisplay, true)
    }

    func testStashedTopologyChangeMovesOnlyHandle() throws {
        let geometry = try makeSecondaryGeometry()
        let original = topology(revision: 1)
        let initialPlacement = PanelStashPlacement(
            side: .right,
            frame: CGRect(x: 3_324, y: 300, width: 36, height: 96)
        )
        let intent = try XCTUnwrap(
            PanelStashPolicy.intent(for: initialPlacement, topology: original)
        )
        let fallback = DisplayTopology(revision: 2, displays: [primary()])

        let decision = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: geometry.frame,
            presentation: .stashed(intent),
            lastAcceptedRevision: 1,
            topology: fallback,
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertNil(decision?.panelFrame)
        XCTAssertEqual(decision?.stashPlacement?.side, .right)
        XCTAssertEqual(decision?.stashPlacement?.frame.maxX, 1_440)
    }

    func testExpandedTopologyChangePreservesAppKitControlledFrame() throws {
        let geometry = try makeSecondaryGeometry()

        let decision = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
            presentation: .expanded,
            lastAcceptedRevision: 1,
            topology: DisplayTopology(revision: 2, displays: [primary()]),
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(decision?.acceptedRevision, 2)
        XCTAssertNil(decision?.panelFrame)
        XCTAssertNil(decision?.stashPlacement)
    }

    func testHiddenTopologyChangeResolvesWithoutDisplayingPanel() throws {
        let geometry = try makeSecondaryGeometry()

        let decision = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: geometry.frame,
            presentation: .hidden,
            lastAcceptedRevision: 1,
            topology: DisplayTopology(revision: 2, displays: [primary()]),
            minimumContentSize: CGSize(width: 360, height: 420),
            frameForContentRect: { $0 }
        )

        XCTAssertNotNil(decision?.panelFrame)
        XCTAssertEqual(decision?.panelFrameShouldDisplay, false)
        XCTAssertNil(decision?.stashPlacement)
    }

    func testDuplicateAndOutOfOrderRevisionsAreIgnored() throws {
        let geometry = try makeSecondaryGeometry()

        let duplicate = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: geometry.frame,
            presentation: .visible,
            lastAcceptedRevision: 3,
            topology: topology(revision: 3),
            minimumContentSize: .zero,
            frameForContentRect: { $0 }
        )
        let stale = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: geometry.frame,
            presentation: .visible,
            lastAcceptedRevision: 3,
            topology: topology(revision: 2),
            minimumContentSize: .zero,
            frameForContentRect: { $0 }
        )

        XCTAssertNil(duplicate)
        XCTAssertNil(stale)
    }

    func testEmptyTopologyAcceptsRevisionWithoutMovingRepresentation() throws {
        let geometry = try makeSecondaryGeometry()

        let decision = PanelTopologyPolicy.resolve(
            committedGeometry: geometry,
            currentPanelFrame: geometry.frame,
            presentation: .visible,
            lastAcceptedRevision: 3,
            topology: DisplayTopology(revision: 4, displays: []),
            minimumContentSize: .zero,
            frameForContentRect: { $0 }
        )

        XCTAssertEqual(decision?.acceptedRevision, 4)
        XCTAssertNil(decision?.panelFrame)
        XCTAssertNil(decision?.stashPlacement)
    }

    private func makeSecondaryGeometry() throws -> PanelGeometry {
        let currentTopology = topology(revision: 1)
        let secondary = try XCTUnwrap(currentTopology.displays.last)
        return try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 680, height: 720),
            frame: CGRect(x: 2_656, y: 311, width: 680, height: 720),
            visibleFrame: secondary.visibleFrame,
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            ),
            displayAffinity: secondary.affinity(in: currentTopology)
        )
    }

    private func topology(revision: UInt64) -> DisplayTopology {
        DisplayTopology(
            revision: revision,
            displays: [
                primary(),
                DisplayDescriptor(
                    identifier: 22,
                    frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                    visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_055),
                    backingScaleFactor: 1,
                    isPrimary: false
                ),
            ]
        )
    }

    private func primary(
        width: CGFloat = 1_440,
        height: CGFloat = 900
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            identifier: 11,
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            visibleFrame: CGRect(x: 0, y: 0, width: width, height: height - 25),
            backingScaleFactor: 2,
            isPrimary: true
        )
    }
}
