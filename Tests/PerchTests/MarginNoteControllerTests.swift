import Foundation
import XCTest
@testable import Perch

@MainActor
final class MarginNoteControllerTests: XCTestCase {
    func testNoteLandsAtTheNotionCursor() throws {
        let target = MarginNoteTargetSpy(hasCursor: true)
        let (controller, store, messages) = try makeController(target: target)

        controller.submit(MarginNote(text: "hello", createdAt: Date(), source: nil))

        XCTAssertEqual(target.pastedMarkdown.count, 1)
        XCTAssertTrue(try XCTUnwrap(target.pastedMarkdown.first).hasPrefix("- hello — _"))
        XCTAssertEqual(controller.waitingNotes, [])
        XCTAssertEqual(store.load(), [])
        XCTAssertEqual(messages.values, ["Noted in Notion."])
    }

    func testNoteWaitsWhenThePageHasNoCursor() throws {
        let target = MarginNoteTargetSpy(hasCursor: false)
        let (controller, store, _) = try makeController(target: target)
        let note = MarginNote(text: "later", createdAt: Date(), source: nil)

        controller.submit(note)

        XCTAssertEqual(target.pastedMarkdown, [])
        XCTAssertEqual(controller.waitingNotes, [note])
        XCTAssertEqual(store.load(), [note])
    }

    func testNoteWaitsWhenNoPageIsLoaded() throws {
        let target = MarginNoteTargetSpy(hasCursor: true)
        target.isAgentStreamTargetAvailable = false
        let (controller, _, _) = try makeController(target: target)

        controller.submit(MarginNote(text: "later", createdAt: Date(), source: nil))

        XCTAssertEqual(target.rememberCount, 0)
        XCTAssertEqual(controller.waitingNotes.count, 1)
    }

    func testNextNoteBringsWaitingNotesAlongInOrder() throws {
        let target = MarginNoteTargetSpy(hasCursor: false)
        let (controller, store, _) = try makeController(target: target)
        controller.submit(MarginNote(text: "first", createdAt: Date(), source: nil))

        target.hasCursor = true
        controller.submit(MarginNote(text: "second", createdAt: Date(), source: nil))

        let markdown = try XCTUnwrap(target.pastedMarkdown.last)
        let lines = markdown.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("- first"))
        XCTAssertTrue(lines[1].hasPrefix("- second"))
        XCTAssertEqual(controller.waitingNotes, [])
        XCTAssertEqual(store.load(), [])
    }

    func testDropWaitingNotesClearsThemOnceTheyLand() throws {
        let target = MarginNoteTargetSpy(hasCursor: false)
        let (controller, _, _) = try makeController(target: target)
        controller.submit(MarginNote(text: "a", createdAt: Date(), source: nil))
        controller.submit(MarginNote(text: "b", createdAt: Date(), source: nil))
        XCTAssertEqual(controller.waitingNotes.count, 2)

        target.hasCursor = true
        controller.dropWaitingNotes()

        XCTAssertEqual(controller.waitingNotes, [])
        XCTAssertEqual(target.pastedMarkdown.count, 1)
    }

    func testFailedPasteKeepsTheNoteWaiting() throws {
        let target = MarginNoteTargetSpy(hasCursor: true)
        target.pasteSucceeds = false
        let (controller, _, _) = try makeController(target: target)

        controller.submit(MarginNote(text: "x", createdAt: Date(), source: nil))

        XCTAssertEqual(controller.waitingNotes.count, 1)
    }

    private func makeController(
        target: MarginNoteTargetSpy
    ) throws -> (MarginNoteController, MarginNoteQueueStore, MessageLog) {
        let suiteName = "MarginNoteControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let store = MarginNoteQueueStore(defaults: defaults)
        let messages = MessageLog()
        let controller = MarginNoteController(
            target: target,
            queueStore: store,
            notify: { messages.values.append($0) }
        )
        return (controller, store, messages)
    }
}

@MainActor
private final class MessageLog {
    var values: [String] = []
}

@MainActor
private final class MarginNoteTargetSpy: AgentStreamTarget {
    var isAgentStreamTargetAvailable = true
    var agentStreamOpaquePageID: String? = "page"
    var hasCursor: Bool
    var pasteSucceeds = true
    private(set) var rememberCount = 0
    private(set) var pastedMarkdown: [String] = []

    init(hasCursor: Bool) {
        self.hasCursor = hasCursor
    }

    func rememberCurrentEditorCursor(completion: @escaping @MainActor (Bool) -> Void) {
        rememberCount += 1
        completion(hasCursor)
    }

    func pasteMarkdownAtSavedEditorCursor(
        _ markdown: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if pasteSucceeds {
            pastedMarkdown.append(markdown)
        }
        completion(pasteSucceeds)
    }
}
