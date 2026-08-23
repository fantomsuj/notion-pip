import XCTest
@testable import Perch

final class ContextSuggestionCardTests: XCTestCase {
    func testPresentationUsesConciseSourceAndQuestion() {
        let presentation = ContextSuggestionCardPresentation(
            applicationName: "Google Chrome",
            sourceDescription: "github.com",
            pageLabel: "Project Brief"
        )

        XCTAssertEqual(presentation.source, "Google Chrome · github.com")
        XCTAssertEqual(presentation.title, "Open Project Brief?")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Perch suggests opening Project Brief for Google Chrome, github.com"
        )
    }

    func testPresentationFallsBackToApplicationName() {
        let presentation = ContextSuggestionCardPresentation(
            applicationName: "Xcode",
            sourceDescription: nil,
            pageLabel: "Build Notes"
        )

        XCTAssertEqual(presentation.source, "Xcode")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Perch suggests opening Build Notes for Xcode"
        )
    }
}
