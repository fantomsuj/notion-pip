import Foundation
import XCTest
@testable import NotionPiP

final class MenuBarIconPreferenceStoreTests: XCTestCase {
    func testMissingPreferenceDefaultsToVisible() throws {
        let defaults = try makeDefaults()

        XCTAssertTrue(MenuBarIconPreferenceStore(defaults: defaults).load())
    }

    func testPersistedFalseLoadsAsHidden() throws {
        let defaults = try makeDefaults()
        let store = MenuBarIconPreferenceStore(defaults: defaults)

        store.save(false)

        XCTAssertFalse(store.load())
    }

    func testPersistedTrueLoadsAsVisible() throws {
        let defaults = try makeDefaults()
        let store = MenuBarIconPreferenceStore(defaults: defaults)

        store.save(true)

        XCTAssertTrue(store.load())
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "MenuBarIconPreferenceStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
