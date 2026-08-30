import Foundation
import XCTest
@testable import Perch

final class StashHandleVisibilityPreferenceStoreTests: XCTestCase {
    func testMissingPreferenceDefaultsToVisible() throws {
        let defaults = try makeDefaults()

        XCTAssertFalse(StashHandleVisibilityPreferenceStore(defaults: defaults).load())
    }

    func testPersistedTrueLoadsAsHidden() throws {
        let defaults = try makeDefaults()
        let store = StashHandleVisibilityPreferenceStore(defaults: defaults)

        store.save(true)

        XCTAssertTrue(store.load())
    }

    func testPersistedFalseLoadsAsVisible() throws {
        let defaults = try makeDefaults()
        let store = StashHandleVisibilityPreferenceStore(defaults: defaults)

        store.save(false)

        XCTAssertFalse(store.load())
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "StashHandleVisibilityPreferenceStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
