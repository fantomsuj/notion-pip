import CoreGraphics
import XCTest

@testable import NotionPiP

final class DisplayTopologyPolicyTests: XCTestCase {
    func testExactIdentifierFollowsDisplayAfterLeftToRightRearrangement() throws {
        let original = topology(
            revision: 1,
            secondary: display(
                id: 22,
                x: -1_920,
                width: 1_920,
                height: 1_080,
                scale: 2
            )
        )
        let affinity = try XCTUnwrap(original.displays.last).affinity(in: original)
        let rearranged = topology(
            revision: 2,
            secondary: display(
                id: 22,
                x: 1_440,
                width: 1_920,
                height: 1_080,
                scale: 2
            )
        )

        let target = DisplayTopologyPolicy.targetDisplay(
            for: affinity,
            currentFrame: CGRect(x: -1_000, y: 200, width: 480, height: 600),
            in: rearranged
        )

        XCTAssertEqual(target?.identifier, 22)
        XCTAssertEqual(target?.frame.minX, 1_440)
    }

    func testStrongSemanticReplacementSurvivesChangedIdentifierAndScale() throws {
        let original = topology(
            revision: 1,
            secondary: display(
                id: 22,
                x: 1_440,
                width: 1_920,
                height: 1_080,
                scale: 1
            )
        )
        let affinity = try XCTUnwrap(original.displays.last).affinity(in: original)
        let replacement = topology(
            revision: 2,
            secondary: display(
                id: 77,
                x: -1_706,
                width: 1_706,
                height: 960,
                scale: 2
            )
        )

        let target = DisplayTopologyPolicy.targetDisplay(
            for: affinity,
            currentFrame: CGRect(x: 900, y: 200, width: 480, height: 600),
            in: replacement
        )

        XCTAssertEqual(target?.identifier, 77)
        XCTAssertFalse(target?.isPrimary ?? true)
    }

    func testMissingSecondaryFallsBackToReachablePrimary() throws {
        let original = topology(
            revision: 1,
            secondary: display(
                id: 22,
                x: 1_440,
                width: 1_920,
                height: 1_080,
                scale: 1
            )
        )
        let affinity = try XCTUnwrap(original.displays.last).affinity(in: original)
        let primaryOnly = DisplayTopology(
            revision: 2,
            displays: [primaryDisplay]
        )

        let target = DisplayTopologyPolicy.targetDisplay(
            for: affinity,
            currentFrame: CGRect(x: 1_600, y: 200, width: 480, height: 600),
            in: primaryOnly
        )

        XCTAssertEqual(target?.identifier, primaryDisplay.identifier)
    }

    func testReplacementDoesNotMistakePrimaryForMissingSecondary() throws {
        let original = topology(
            revision: 1,
            secondary: display(
                id: 22,
                x: 1_440,
                width: 1_440,
                height: 900,
                scale: 2
            )
        )
        let affinity = try XCTUnwrap(original.displays.last).affinity(in: original)
        let changedPrimary = DisplayDescriptor(
            identifier: 99,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
            backingScaleFactor: 2,
            isPrimary: true
        )
        let topology = DisplayTopology(revision: 2, displays: [changedPrimary])

        let target = DisplayTopologyPolicy.semanticReplacement(
            for: affinity,
            in: topology
        )

        XCTAssertNil(target)
    }

    func testFallbackTieIsIndependentOfInputOrdering() {
        let left = display(id: 31, x: -1_000, width: 1_000, height: 800, scale: 2)
        let right = display(id: 32, x: 0, width: 1_000, height: 800, scale: 2)
        let frame = CGRect(x: -240, y: 200, width: 480, height: 400)

        let first = DisplayTopologyPolicy.targetDisplay(
            for: nil,
            currentFrame: frame,
            in: DisplayTopology(revision: 1, displays: [left, right])
        )
        let second = DisplayTopologyPolicy.targetDisplay(
            for: nil,
            currentFrame: frame,
            in: DisplayTopology(revision: 1, displays: [right, left])
        )

        XCTAssertEqual(first?.identifier, second?.identifier)
        XCTAssertEqual(first?.identifier, 31)
    }

    private var primaryDisplay: DisplayDescriptor {
        DisplayDescriptor(
            identifier: 11,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
            backingScaleFactor: 2,
            isPrimary: true
        )
    }

    private func topology(
        revision: UInt64,
        secondary: DisplayDescriptor
    ) -> DisplayTopology {
        DisplayTopology(
            revision: revision,
            displays: [primaryDisplay, secondary]
        )
    }

    private func display(
        id: UInt32,
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            identifier: id,
            frame: CGRect(x: x, y: 0, width: width, height: height),
            visibleFrame: CGRect(x: x, y: 0, width: width, height: height - 25),
            backingScaleFactor: scale,
            isPrimary: false
        )
    }
}
