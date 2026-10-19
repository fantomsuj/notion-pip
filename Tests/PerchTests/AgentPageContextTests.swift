import Combine
import XCTest

@testable import Perch

final class AgentPageContextTests: XCTestCase {
    private let pageURL = URL(string: "https://www.notion.com/Roadmap-0123456789abcdef0123456789abcdef")!
    private let copiedAt = Date(timeIntervalSince1970: 1_790_000_000)

    func testSnapshotAcceptsTheReaderScriptsShape() throws {
        let value: [String: Any] = [
            "version": 1,
            "title": "Roadmap\nQ4",
            "body": "- one\n- two",
            "coverage": "blocks",
            "unrecognized": 2,
            "truncated": false,
        ]
        let snapshot = try XCTUnwrap(
            AgentPageSnapshot(
                javaScriptValue: value,
                url: pageURL,
                fallbackTitle: "Ignored"
            )
        )

        XCTAssertEqual(snapshot.title, "Roadmap Q4")
        XCTAssertEqual(snapshot.url, pageURL)
        XCTAssertEqual(snapshot.coverage, .renderedBlocks)
        XCTAssertEqual(snapshot.wordCount, 4)
        XCTAssertFalse(snapshot.wasTruncatedByReader)
    }

    func testSnapshotUsesTheFallbackTitleAndTextCoverage() throws {
        let textValue: [String: Any] = [
            "version": 1, "title": "  ", "body": "Hi", "coverage": "text",
        ]
        let snapshot = try XCTUnwrap(
            AgentPageSnapshot(
                javaScriptValue: textValue,
                url: pageURL,
                fallbackTitle: "Course page"
            )
        )

        XCTAssertEqual(snapshot.title, "Course page")
        XCTAssertEqual(snapshot.coverage, .visibleText)
    }

    func testSnapshotRejectsUnexpectedValues() {
        let wrongVersion: [String: Any] = ["version": 2, "body": "", "coverage": "blocks"]
        let missingBody: [String: Any] = ["version": 1, "coverage": "blocks"]
        let unknownCoverage: [String: Any] = ["version": 1, "body": "", "coverage": "html"]
        let invalidValues: [Any?] = [nil, "text", wrongVersion, missingBody, unknownCoverage]

        for value in invalidValues {
            XCTAssertNil(AgentPageSnapshot(javaScriptValue: value, url: pageURL, fallbackTitle: ""))
        }
    }

    func testFormatterWritesFrontMatterTitleAndBody() {
        let snapshot = AgentPageSnapshot(
            title: #"Q4 "launch" plan"#,
            url: pageURL,
            body: "## Goals\n\nShip it.",
            coverage: .renderedBlocks
        )

        let markdown = AgentPageContextFormatter.markdown(for: snapshot, copiedAt: copiedAt)

        XCTAssertEqual(
            markdown,
            """
            ---
            source: Perch
            title: "Q4 \\"launch\\" plan"
            url: "\(pageURL.absoluteString)"
            copied: \(copiedAt.formatted(.iso8601))
            coverage: rendered blocks only
            ---

            # Q4 "launch" plan

            ## Goals

            Ship it.

            """
        )
    }

    func testFormatterWritesOnlyTheHeadingForLinkOnlySnapshots() {
        let markdown = AgentPageContextFormatter.markdown(
            for: .linkOnly(title: "", url: pageURL),
            copiedAt: copiedAt
        )

        XCTAssertTrue(markdown.contains("coverage: link only\n"))
        XCTAssertTrue(markdown.hasSuffix("---\n\n# Untitled\n"))
    }

    func testFormatterCapsOutputAndMarksTruncation() {
        let body = String(repeating: "é", count: AgentPageContextFormatter.maximumUTF8Bytes)
        let snapshot = AgentPageSnapshot(
            title: "Long",
            url: pageURL,
            body: body,
            coverage: .renderedBlocks
        )

        let markdown = AgentPageContextFormatter.markdown(for: snapshot, copiedAt: copiedAt)

        XCTAssertLessThanOrEqual(markdown.utf8.count, AgentPageContextFormatter.maximumUTF8Bytes)
        XCTAssertTrue(markdown.contains("truncated: true\n"))
        XCTAssertTrue(markdown.hasSuffix(AgentPageContextFormatter.truncationMarker + "\n"))
    }
}

@MainActor
final class AgentPageCopyControllerTests: XCTestCase {
    private let pageURL = URL(string: "https://www.notion.com/Roadmap-0123456789abcdef0123456789abcdef")!

    func testCopyWritesMarkdownAndShowsWordCount() {
        var clipboard: [String] = []
        let snapshot = AgentPageSnapshot(
            title: "Roadmap",
            url: pageURL,
            body: "Ship the roadmap",
            coverage: .renderedBlocks
        )
        let controller = AgentPageCopyController(
            readPage: { $0(.success(snapshot)) },
            writeToClipboard: { clipboard.append($0); return true },
            now: { Date(timeIntervalSince1970: 0) },
            scheduleFeedbackClear: { _, _ in AnyCancellable {} }
        )

        controller.copy()

        XCTAssertEqual(
            clipboard,
            [AgentPageContextFormatter.markdown(for: snapshot, copiedAt: Date(timeIntervalSince1970: 0))]
        )
        XCTAssertEqual(
            controller.feedback,
            .copied(wordCount: 3, coverage: .renderedBlocks, truncated: false)
        )
        XCTAssertEqual(controller.feedback?.message, "Copied for agent · 3 words")
    }

    func testCopyWithoutAPageLeavesTheClipboardAlone() {
        var clipboard: [String] = []
        let controller = AgentPageCopyController(
            readPage: { $0(.failure(.noPage)) },
            writeToClipboard: { clipboard.append($0); return true },
            scheduleFeedbackClear: { _, _ in AnyCancellable {} }
        )

        controller.copy()

        XCTAssertTrue(clipboard.isEmpty)
        XCTAssertEqual(controller.feedback, .noPage)
        XCTAssertEqual(controller.feedback?.isError, true)
    }

    func testLinkOnlyAndClipboardFailuresHaveTheirOwnMessages() {
        var writeSucceeds = true
        let url = pageURL
        let controller = AgentPageCopyController(
            readPage: { completion in
                completion(.success(.linkOnly(title: "Roadmap", url: url)))
            },
            writeToClipboard: { _ in writeSucceeds },
            scheduleFeedbackClear: { _, _ in AnyCancellable {} }
        )

        controller.copy()
        XCTAssertEqual(controller.feedback?.message, "Copied page link for agent")

        writeSucceeds = false
        controller.copy()
        XCTAssertEqual(controller.feedback, .clipboardUnavailable)
    }

    func testFeedbackClearsAfterTheScheduledDelay() {
        var scheduledDelays: [TimeInterval] = []
        var clear: (@MainActor () -> Void)?
        let controller = AgentPageCopyController(
            readPage: { $0(.failure(.noPage)) },
            writeToClipboard: { _ in true },
            scheduleFeedbackClear: { delay, action in
                scheduledDelays.append(delay)
                clear = action
                return AnyCancellable {}
            }
        )

        controller.copy()
        XCTAssertNotNil(controller.feedback)

        clear?()

        XCTAssertNil(controller.feedback)
        XCTAssertEqual(scheduledDelays, [AgentPageCopyController.feedbackDuration])
    }

    func testOverlappingCopiesReadThePageOnce() {
        var pending: [@MainActor (Result<AgentPageSnapshot, AgentPageCopyError>) -> Void] = []
        let controller = AgentPageCopyController(
            readPage: { pending.append($0) },
            writeToClipboard: { _ in true },
            scheduleFeedbackClear: { _, _ in AnyCancellable {} }
        )

        controller.copy()
        controller.copy()

        XCTAssertEqual(pending.count, 1)
        pending.first?(.failure(.noPage))
        controller.copy()
        XCTAssertEqual(pending.count, 2)
    }
}
