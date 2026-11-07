import Foundation
import XCTest
@testable import Perch

final class CursorToolsStoresTests: XCTestCase {
    func testCursorToolsAreOffUntilTurnedOn() throws {
        let defaults = try makeDefaults()
        let store = CursorToolsPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.load())
        store.save(true)
        XCTAssertTrue(store.load())
    }

    func testWaitingNotesRoundTripInOrder() throws {
        let defaults = try makeDefaults()
        let store = MarginNoteQueueStore(defaults: defaults)
        let notes = [
            MarginNote(text: "one", createdAt: Date(timeIntervalSince1970: 1), source: nil),
            MarginNote(
                text: "two",
                createdAt: Date(timeIntervalSince1970: 2),
                source: MarginNoteSource(applicationName: "Mail", windowTitle: "Inbox")
            ),
        ]

        store.save(notes)

        XCTAssertEqual(store.load(), notes)
    }

    func testSavingNoNotesClearsTheQueue() throws {
        let defaults = try makeDefaults()
        let store = MarginNoteQueueStore(defaults: defaults)
        store.save([MarginNote(text: "one", createdAt: Date(), source: nil)])

        store.save([])

        XCTAssertNil(defaults.object(forKey: MarginNoteQueueStore.key))
        XCTAssertEqual(store.load(), [])
    }

    func testQueueKeepsOnlyTheNewestNotes() throws {
        let defaults = try makeDefaults()
        let store = MarginNoteQueueStore(defaults: defaults)
        let notes = (0 ..< MarginNoteQueueStore.maximumCount + 5).map {
            MarginNote(text: "\($0)", createdAt: Date(timeIntervalSince1970: Double($0)), source: nil)
        }

        store.save(notes)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, MarginNoteQueueStore.maximumCount)
        XCTAssertEqual(loaded.first?.text, "5")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "CursorToolsStoresTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
