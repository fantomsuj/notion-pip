import Foundation
import XCTest

@testable import NotionPiP

final class PanelSizePreferencesStoreTests: XCTestCase {
    func testMissingPreferencesReturnNilForLegacyFrameCompatibility() throws {
        let defaults = try makeDefaults()

        XCTAssertNil(PanelSizePreferencesStore(defaults: defaults).load())
    }

    func testPreferencesRoundTripWithVersionDefaultCustomAndWorkingSize() throws {
        let defaults = try makeDefaults()
        let store = PanelSizePreferencesStore(defaults: defaults)
        var preferences = PanelSizePreferences.default
        let custom = try preferences.addCustomPreset(
            id: UUID(uuidString: "55D9B0D5-FA64-425A-9435-CCCF7CCEF621")!,
            name: "Research",
            contentSize: PanelContentSize(width: 740, height: 920)
        )
        try preferences.setDefaultPreset(id: .custom(custom.id))
        preferences.setLastExplicitWorkingContentSize(
            try PanelContentSize(width: 611.5, height: 777.5)
        )

        try store.save(preferences)

        XCTAssertEqual(store.load(), preferences)
        XCTAssertEqual(store.load()?.version, PanelSizePreferences.currentVersion)
    }

    func testCorruptedPreferencesFallBackToVerticalDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not JSON".utf8), forKey: PanelSizePreferencesStore.key)

        XCTAssertEqual(
            PanelSizePreferencesStore(defaults: defaults).load(),
            .default
        )
    }

    func testWrongUserDefaultsValueTypeFallsBackToVerticalDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set("not data", forKey: PanelSizePreferencesStore.key)

        XCTAssertEqual(
            PanelSizePreferencesStore(defaults: defaults).load(),
            .default
        )
    }

    func testUnsupportedStoredVersionFallsBackToVerticalDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(
            Data(
                """
                {
                  "version": 999,
                  "defaultPresetID": "builtin:wide",
                  "customPresets": []
                }
                """.utf8
            ),
            forKey: PanelSizePreferencesStore.key
        )

        XCTAssertEqual(
            PanelSizePreferencesStore(defaults: defaults).load(),
            .default
        )
    }

    func testInvalidStoredCustomPresetFallsBackToVerticalDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(
            Data(
                """
                {
                  "version": 1,
                  "defaultPresetID": "builtin:comfortable",
                  "customPresets": [{
                    "id": "55D9B0D5-FA64-425A-9435-CCCF7CCEF621",
                    "name": "Invalid",
                    "contentSize": {"width": 359, "height": 800}
                  }]
                }
                """.utf8
            ),
            forKey: PanelSizePreferencesStore.key
        )

        XCTAssertEqual(
            PanelSizePreferencesStore(defaults: defaults).load(),
            .default
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "PanelSizePreferencesStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
