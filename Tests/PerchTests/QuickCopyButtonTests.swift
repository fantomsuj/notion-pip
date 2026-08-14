import XCTest
@testable import Perch

@MainActor
final class QuickCopyButtonTests: XCTestCase {
    func testUsesCompactBottomLeftSizingAndAccessibleCopy() {
        XCTAssertEqual(QuickCopyButton.controlSize, 30)
        XCTAssertEqual(QuickCopyButton.edgeInset, 8)
        XCTAssertEqual(
            QuickCopyButton.accessibilityLabel,
            "Quick Copy selections to Notion"
        )
        XCTAssertEqual(
            QuickCopyButton.helpText,
            "Place the cursor in Notion, turn on Quick Copy, "
                + "then select text in another app"
        )
    }

    func testPresentationDistinguishesEverySessionState() {
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .off),
            QuickCopyButtonPresentation(
                systemImage: "text.append",
                title: "Quick Copy to Notion",
                statusMessage: nil,
                appearance: .off,
                showsProgress: false
            )
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .armed).title,
            "Quick Copy on"
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .inserting).showsProgress,
            true
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .added),
            QuickCopyButtonPresentation(
                systemImage: "checkmark",
                title: "Added",
                statusMessage: nil,
                appearance: .active,
                showsProgress: false
            )
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .permissionNeeded).appearance,
            .permissionNeeded
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .warning("Unsupported")).appearance,
            .warning
        )
        XCTAssertEqual(
            QuickCopyButtonPresentation(state: .failed("Stale")).appearance,
            .failed
        )
    }
}
