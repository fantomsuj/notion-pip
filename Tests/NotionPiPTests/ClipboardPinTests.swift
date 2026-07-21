import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class ClipboardPinTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"

    func testValidClipboardIsReadOnceAndRoutedToPanel() {
        let panel = FakePanelCoordinator()
        let pasteboard = CountingPasteboard(
            value: "https://www.notion.so/Project-\(firstPageID)"
        )
        var focusRequests = 0
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: pasteboard,
            requestPageURLFocus: { focusRequests += 1 }
        )

        coordinator.pinFromClipboard()

        XCTAssertEqual(pasteboard.readCount, 1)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertEqual(focusRequests, 0)
    }

    func testInvalidClipboardKeepsCurrentPageAndRequestsURLFieldFocus() throws {
        let panel = FakePanelCoordinator()
        let currentPage = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Current-\(firstPageID)"))
        )
        panel.show(page: currentPage)
        let pasteboard = CountingPasteboard(value: "https://example.com/not-notion")
        var focusRequests = 0
        let coordinator = PinCoordinator(
            panelCoordinator: panel,
            pasteboard: pasteboard,
            requestPageURLFocus: { focusRequests += 1 }
        )

        coordinator.pinFromClipboard()

        XCTAssertEqual(pasteboard.readCount, 1)
        XCTAssertEqual(panel.currentPage, currentPage)
        XCTAssertEqual(panel.shownPages.count, 1)
        XCTAssertTrue(panel.replacedPages.isEmpty)
        XCTAssertEqual(panel.hideCount, 0)
        XCTAssertEqual(focusRequests, 1)
    }
}

private final class CountingPasteboard: PasteboardReading {
    let value: String?
    private(set) var readCount = 0

    init(value: String?) {
        self.value = value
    }

    func readString() -> String? {
        readCount += 1
        return value
    }
}
