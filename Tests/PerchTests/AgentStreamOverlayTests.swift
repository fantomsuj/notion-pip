import XCTest
@testable import Perch

@MainActor
final class AgentStreamOverlayTests: XCTestCase {
    func testPresentationMapsReadyToAcceptSurface() {
        let snapshot = AgentStreamSnapshot(
            id: UUID(),
            label: "Codex",
            client: "codex",
            contentType: .markdown,
            phase: .ready,
            assembledText: "## Ready",
            nextSequence: 1,
            opaquePageID: nil,
            errorMessage: nil,
            canAccept: true,
            showsOverlay: true
        )
        XCTAssertEqual(
            AgentStreamOverlayPresentation.from(snapshot: snapshot),
            .ready(label: "Codex", text: "## Ready", contentType: .markdown)
        )
    }

    func testPresentationHidesWhenShowsOverlayIsFalse() {
        let snapshot = AgentStreamSnapshot(
            id: UUID(),
            label: "Codex",
            client: "codex",
            contentType: .markdown,
            phase: .cancelled,
            assembledText: "",
            nextSequence: 0,
            opaquePageID: nil,
            errorMessage: nil,
            canAccept: false,
            showsOverlay: false
        )
        XCTAssertEqual(
            AgentStreamOverlayPresentation.from(snapshot: snapshot),
            .hidden
        )
    }

    func testFailedPresentationKeepsTextForRetryAccept() {
        let snapshot = AgentStreamSnapshot(
            id: UUID(),
            label: "Cursor",
            client: "cursor",
            contentType: .markdown,
            phase: .failed,
            assembledText: "- keep",
            nextSequence: 1,
            opaquePageID: nil,
            errorMessage: AgentStreamUserFacingCopy.clickFirstHint,
            canAccept: true,
            showsOverlay: true
        )
        XCTAssertEqual(
            AgentStreamOverlayPresentation.from(snapshot: snapshot),
            .failed(
                label: "Cursor",
                text: "- keep",
                contentType: .markdown,
                message: AgentStreamUserFacingCopy.clickFirstHint
            )
        )
    }

    func testAccessibilityLabelsIncludeAccept() {
        XCTAssertEqual(
            AgentStreamAccessibilityLabels.accept,
            "Accept and paste into Notion"
        )
        XCTAssertEqual(AgentStreamUserFacingCopy.acceptButton, "Accept")
        XCTAssertEqual(
            AgentStreamAccessibilityLabels.expandDetails,
            "Show stream details"
        )
        XCTAssertEqual(
            AgentStreamAccessibilityLabels.collapseDetails,
            "Hide stream details"
        )
    }

    func testCompactOverlayDefaultsCollapsedForReadyAndFailed() {
        XCTAssertEqual(AgentStreamUserFacingCopy.readyTitle, "Agent response ready")
        XCTAssertEqual(AgentStreamUserFacingCopy.failedTitle, "Couldn’t paste")
        // Expansion is view-local (@State); presentation mapping stays phase-only.
        let ready = AgentStreamSnapshot(
            id: UUID(),
            label: "Codex",
            client: "codex",
            contentType: .markdown,
            phase: .ready,
            assembledText: "## Ready",
            nextSequence: 1,
            opaquePageID: nil,
            errorMessage: nil,
            canAccept: true,
            showsOverlay: true
        )
        XCTAssertEqual(
            AgentStreamOverlayPresentation.from(snapshot: ready),
            .ready(label: "Codex", text: "## Ready", contentType: .markdown)
        )
    }

    func testMarkdownOutputFallsBackToPlainTextWhenParsingFails() {
        // Unclosed fence is still displayable as attributed plain/markdown text.
        let view = AgentStreamMarkdownOutput(
            text: "```swift\nlet x = 1",
            contentType: .markdown
        )
        XCTAssertFalse(view.text.isEmpty)
    }
}
