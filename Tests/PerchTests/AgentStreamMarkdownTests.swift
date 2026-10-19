import Foundation
import XCTest
@testable import Perch

@MainActor
final class AgentStreamMarkdownTests: XCTestCase {
    func testParsesHeadingsListsQuotesCodeAndDividers() {
        let blocks = AgentStreamMarkdown.blocks(
            from: """
            # Plan ##
            Intro with **bold**
            and a second line.

            - one
              - nested
            2. second
            - [ ] todo
            - [x] done
            > quoted
            > still quoted
            ```swift
            # not a heading
            ```
            ---
            ### Small
            """
        )

        XCTAssertEqual(
            blocks.map(\.kind),
            [
                .heading(level: 1),
                .paragraph,
                .listItem(marker: "•", indentLevel: 0),
                .listItem(marker: "•", indentLevel: 1),
                .listItem(marker: "2.", indentLevel: 0),
                .listItem(marker: "☐", indentLevel: 0),
                .listItem(marker: "☑", indentLevel: 0),
                .quote,
                .code,
                .divider,
                .heading(level: 3),
            ]
        )
        XCTAssertEqual(
            blocks.map { String($0.content.characters) },
            [
                "Plan",
                "Intro with bold\nand a second line.",
                "one",
                "nested",
                "second",
                "todo",
                "done",
                "quoted\nstill quoted",
                "# not a heading",
                "",
                "Small",
            ]
        )
    }

    func testInlineMarkdownStillRendersInsideBlocks() throws {
        let block = try XCTUnwrap(AgentStreamMarkdown.blocks(from: "- a **bold** word").first)

        let isBold = block.content.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        XCTAssertTrue(isBold)
        XCTAssertEqual(String(block.content.characters), "a bold word")
    }

    func testHashtagsAndEmphasisAreNotHeadingsOrLists() {
        let blocks = AgentStreamMarkdown.blocks(from: "#hashtag\n**bold** start\n*emphasis*")

        XCTAssertEqual(blocks.map(\.kind), [.paragraph])
    }

    func testUnclosedFenceKeepsStreamingTextAsCode() {
        let blocks = AgentStreamMarkdown.blocks(from: "```swift\nlet x = 1\n- not a list")

        XCTAssertEqual(blocks.map(\.kind), [.code])
        XCTAssertEqual(String(blocks[0].content.characters), "let x = 1\n- not a list")
    }

    func testWindowsLineEndingsSplitLines() {
        let blocks = AgentStreamMarkdown.blocks(from: "# Title\r\n- item\r\n")

        XCTAssertEqual(
            blocks.map(\.kind),
            [.heading(level: 1), .listItem(marker: "•", indentLevel: 0)]
        )
    }

    func testRendererMatchesFullParseAtEveryStepOfAStream() {
        let document = """
        # Release notes

        Perch now **streams** faster.
        #hashtag continues the paragraph

        - first
        - second
          continued
        1. ordered
        > quote
        lazy line

        ```
        code
        ```
        ---
        ## Café ✨
        Last line
        """
        let renderer = AgentStreamMarkdownRenderer()
        var streamed = ""
        for character in document {
            streamed.append(character)
            XCTAssertEqual(
                renderer.blocks(for: streamed, contentType: .markdown),
                AgentStreamMarkdown.blocks(from: streamed),
                "Mismatch after \(streamed.debugDescription)"
            )
        }
    }

    func testRendererOnlyReparsesTheTailOfALongStream() {
        let renderer = AgentStreamMarkdownRenderer()
        var streamed = ""
        for index in 0..<200 {
            streamed += "- item \(index)\n"
            _ = renderer.blocks(for: streamed, contentType: .markdown)
        }

        streamed += "- item 200"
        let blocks = renderer.blocks(for: streamed, contentType: .markdown)

        XCTAssertEqual(blocks.count, 201)
        XCTAssertLessThanOrEqual(renderer.lastParsedBlockCount, 2)
    }

    func testRendererStartsOverWhenTextIsReplaced() {
        let renderer = AgentStreamMarkdownRenderer()
        _ = renderer.blocks(for: "# One\n- a\n- b\n", contentType: .markdown)

        let blocks = renderer.blocks(for: "Different\n", contentType: .markdown)

        XCTAssertEqual(blocks, AgentStreamMarkdown.blocks(from: "Different\n"))
    }

    func testRendererReusesBlocksWhenTextIsUnchanged() {
        let renderer = AgentStreamMarkdownRenderer()
        let first = renderer.blocks(for: "# Same", contentType: .markdown)

        let second = renderer.blocks(for: "# Same", contentType: .markdown)

        XCTAssertEqual(first, second)
        XCTAssertEqual(renderer.lastParsedBlockCount, 0)
    }

    func testAutoScrollFollowsGrowthUntilUserScrollsUp() {
        var autoScroll = AgentStreamAutoScroll()
        XCTAssertFalse(
            autoScroll.update(contentMinY: 0, contentHeight: 100, viewportHeight: 220)
        )

        // New text while following jumps to the bottom.
        XCTAssertTrue(
            autoScroll.update(contentMinY: 0, contentHeight: 400, viewportHeight: 220)
        )
        // Our own jump lands at the bottom, so we keep following.
        XCTAssertFalse(
            autoScroll.update(contentMinY: -180, contentHeight: 400, viewportHeight: 220)
        )
        XCTAssertTrue(autoScroll.isFollowing)

        // The user scrolls up: growth no longer moves the view.
        XCTAssertFalse(
            autoScroll.update(contentMinY: -40, contentHeight: 400, viewportHeight: 220)
        )
        XCTAssertFalse(autoScroll.isFollowing)
        XCTAssertFalse(
            autoScroll.update(contentMinY: -40, contentHeight: 600, viewportHeight: 220)
        )

        // Scrolling back near the bottom resumes following.
        XCTAssertFalse(
            autoScroll.update(contentMinY: -370, contentHeight: 600, viewportHeight: 220)
        )
        XCTAssertTrue(autoScroll.isFollowing)
        XCTAssertTrue(
            autoScroll.update(contentMinY: -370, contentHeight: 700, viewportHeight: 220)
        )
    }
}
