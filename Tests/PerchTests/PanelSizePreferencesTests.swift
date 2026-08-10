import CoreGraphics
import Foundation
import XCTest

@testable import Perch

final class PanelSizePreferencesTests: XCTestCase {
    func testBuiltInPresetsHaveStableOrderNamesAndSizes() {
        XCTAssertEqual(
            BuiltInPanelSizePreset.allCases,
            [.horizontal, .vertical]
        )
        XCTAssertEqual(
            BuiltInPanelSizePreset.horizontal.contentSize(
                forScreenSize: CGSize(width: 1_440, height: 900)
            ),
            try PanelContentSize(width: 760, height: 520)
        )
        XCTAssertEqual(
            BuiltInPanelSizePreset.vertical.contentSize(
                forScreenSize: CGSize(width: 1_440, height: 900)
            ),
            try PanelContentSize(width: 480, height: 720)
        )
        XCTAssertEqual(BuiltInPanelSizePreset.horizontal.name, "Horizontal")
        XCTAssertEqual(BuiltInPanelSizePreset.vertical.name, "Vertical")
    }

    func testLegacyBuiltInIdentifiersDecodeIntoOrientationPresets() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(
                PanelSizePresetID.self,
                from: Data("\"builtin:compact\"".utf8)
            ),
            .vertical
        )
        XCTAssertEqual(
            try decoder.decode(
                PanelSizePresetID.self,
                from: Data("\"builtin:comfortable\"".utf8)
            ),
            .vertical
        )
        XCTAssertEqual(
            try decoder.decode(
                PanelSizePresetID.self,
                from: Data("\"builtin:wide\"".utf8)
            ),
            .horizontal
        )
    }

    func testVersionOnePreferencesMigrateWithoutDiscardingWorkingSize() throws {
        let data = Data(
            """
            {
              "version": 1,
              "defaultPresetID": "builtin:wide",
              "customPresets": [],
              "lastExplicitWorkingContentSize": {"width": 803, "height": 657}
            }
            """.utf8
        )

        let preferences = try JSONDecoder().decode(PanelSizePreferences.self, from: data)

        XCTAssertEqual(preferences.version, PanelSizePreferences.currentVersion)
        XCTAssertEqual(preferences.defaultPresetID, .horizontal)
        XCTAssertEqual(
            preferences.lastExplicitWorkingContentSize,
            try PanelContentSize(width: 803, height: 657)
        )
    }

    func testContentSizeValidationRejectsUnsafeDimensions() throws {
        XCTAssertThrowsError(try PanelContentSize(width: .infinity, height: 500)) {
            XCTAssertEqual($0 as? PanelSizePreferencesError, .nonFiniteDimensions)
        }
        XCTAssertThrowsError(try PanelContentSize(width: 359, height: 420)) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .dimensionsBelowMinimum(minimumWidth: 360, minimumHeight: 420)
            )
        }
        XCTAssertThrowsError(try PanelContentSize(width: 360, height: 4_097)) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .dimensionsAboveMaximum(maximum: 4_096)
            )
        }

        XCTAssertNoThrow(try PanelContentSize(width: 360, height: 420))
        XCTAssertNoThrow(try PanelContentSize(width: 4_096, height: 4_096))
    }

    func testCustomPresetTrimsNameAndRequiresWholePointDimensions() throws {
        let preset = try CustomPanelSizePreset(
            name: "  Focused\n",
            contentSize: PanelContentSize(width: 512, height: 640)
        )
        XCTAssertEqual(preset.name, "Focused")

        XCTAssertThrowsError(
            try CustomPanelSizePreset(
                name: "Fractional",
                contentSize: PanelContentSize(width: 512.5, height: 640)
            )
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .dimensionsMustBeWholePoints
            )
        }
    }

    func testCustomPresetRejectsEmptyAndOverlongNames() throws {
        let size = try PanelContentSize(width: 512, height: 640)
        XCTAssertThrowsError(
            try CustomPanelSizePreset(name: " \n ", contentSize: size)
        ) {
            XCTAssertEqual($0 as? PanelSizePreferencesError, .emptyName)
        }
        XCTAssertThrowsError(
            try CustomPanelSizePreset(
                name: String(repeating: "a", count: 41),
                contentSize: size
            )
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .nameTooLong(maximum: 40)
            )
        }
    }

    func testAddAndUpdateCustomPresetPreserveStableID() throws {
        var preferences = PanelSizePreferences.default
        let id = UUID()
        let original = try preferences.addCustomPreset(
            id: id,
            name: "Writing",
            contentSize: PanelContentSize(width: 500, height: 700)
        )

        try preferences.updateCustomPreset(
            id: id,
            name: "Editing",
            contentSize: PanelContentSize(width: 620, height: 800)
        )

        XCTAssertEqual(original.id, id)
        XCTAssertEqual(preferences.customPresets.first?.id, id)
        XCTAssertEqual(preferences.customPresets.first?.name, "Editing")
        XCTAssertEqual(
            preferences.customPresets.first?.contentSize,
            try PanelContentSize(width: 620, height: 800)
        )
    }

    func testNamesMustBeUniqueIgnoringCaseAndBuiltInNamesAreReserved() throws {
        var preferences = PanelSizePreferences.default
        _ = try preferences.addCustomPreset(
            name: "Writing",
            contentSize: PanelContentSize(width: 500, height: 700)
        )

        XCTAssertThrowsError(
            try preferences.addCustomPreset(
                name: " writing ",
                contentSize: PanelContentSize(width: 600, height: 800)
            )
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .duplicateName("writing")
            )
        }
        XCTAssertThrowsError(
            try preferences.addCustomPreset(
                name: "HORIZONTAL",
                contentSize: PanelContentSize(width: 420, height: 520)
            )
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .duplicateName("HORIZONTAL")
            )
        }
    }

    func testCustomPresetLimitIsTwelve() throws {
        var preferences = PanelSizePreferences.default
        for index in 0..<PanelSizePreferences.maximumCustomPresetCount {
            try preferences.addCustomPreset(
                name: "Preset \(index)",
                contentSize: PanelContentSize(
                    width: Double(400 + index),
                    height: 500
                )
            )
        }

        XCTAssertThrowsError(
            try preferences.addCustomPreset(
                name: "One Too Many",
                contentSize: PanelContentSize(width: 500, height: 600)
            )
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .customPresetLimitReached(maximum: 12)
            )
        }
    }

    func testDefaultSelectionResolvesBuiltInAndCustomPresets() throws {
        var preferences = PanelSizePreferences.default
        let custom = try preferences.addCustomPreset(
            name: "Review",
            contentSize: PanelContentSize(width: 720, height: 900)
        )

        try preferences.setDefaultPreset(id: .horizontal)
        XCTAssertEqual(preferences.defaultPresetID, .horizontal)
        XCTAssertEqual(preferences.defaultPreset, .builtIn(.horizontal))

        try preferences.setDefaultPreset(id: .custom(custom.id))
        XCTAssertEqual(preferences.defaultPresetID, .custom(custom.id))
        XCTAssertEqual(preferences.defaultPreset, .custom(custom))
    }

    func testDeletingDefaultCustomPresetFallsBackToVertical() throws {
        var preferences = PanelSizePreferences.default
        let custom = try preferences.addCustomPreset(
            name: "Review",
            contentSize: PanelContentSize(width: 720, height: 900)
        )
        try preferences.setDefaultPreset(id: .custom(custom.id))
        preferences.setLastExplicitWorkingContentSize(
            try PanelContentSize(width: 800, height: 1_000)
        )

        XCTAssertTrue(preferences.deleteCustomPreset(id: custom.id))

        XCTAssertEqual(preferences.defaultPresetID, .vertical)
        XCTAssertEqual(
            preferences.lastExplicitWorkingContentSize,
            try PanelContentSize(width: 800, height: 1_000)
        )
    }

    func testUnknownPresetCannotBecomeDefault() {
        var preferences = PanelSizePreferences.default
        let missingID = UUID()

        XCTAssertThrowsError(
            try preferences.setDefaultPreset(id: .custom(missingID))
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .presetNotFound(.custom(missingID))
            )
        }
        XCTAssertEqual(preferences.defaultPresetID, .vertical)
    }

    func testPresetIdentifiersUseStableCodableStrings() throws {
        let customID = UUID(uuidString: "C087FAE9-31D0-40A8-A3DD-5C876AB9CB18")!
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(
            String(data: try encoder.encode(PanelSizePresetID.horizontal), encoding: .utf8),
            "\"builtin:horizontal\""
        )
        XCTAssertEqual(
            try decoder.decode(
                PanelSizePresetID.self,
                from: Data(
                    "\"custom:c087fae9-31d0-40a8-a3dd-5c876ab9cb18\"".utf8
                )
            ),
            .custom(customID)
        )
    }
}
