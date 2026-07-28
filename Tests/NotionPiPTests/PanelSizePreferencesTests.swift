import CoreGraphics
import Foundation
import XCTest

@testable import NotionPiP

final class PanelSizePreferencesTests: XCTestCase {
    func testBuiltInPresetsHaveStableOrderNamesAndSizes() {
        XCTAssertEqual(
            BuiltInPanelSizePreset.allCases,
            [.compact, .comfortable, .wide]
        )
        XCTAssertEqual(
            BuiltInPanelSizePreset.compact.contentSize(
                forScreenSize: CGSize(width: 1_440, height: 900)
            ),
            try PanelContentSize(width: 420, height: 520)
        )
        XCTAssertEqual(
            BuiltInPanelSizePreset.wide.contentSize(
                forScreenSize: CGSize(width: 1_440, height: 900)
            ),
            try PanelContentSize(width: 680, height: 720)
        )
        XCTAssertEqual(BuiltInPanelSizePreset.compact.name, "Compact")
        XCTAssertEqual(BuiltInPanelSizePreset.comfortable.name, "Comfortable")
        XCTAssertEqual(BuiltInPanelSizePreset.wide.name, "Wide")
    }

    func testComfortableSizeUsesAdaptiveClampedScreenFormula() throws {
        XCTAssertEqual(
            BuiltInPanelSizePreset.comfortable.contentSize(
                forScreenSize: CGSize(width: 1_000, height: 700)
            ),
            try PanelContentSize(width: 480, height: 560)
        )
        XCTAssertEqual(
            BuiltInPanelSizePreset.comfortable.contentSize(
                forScreenSize: CGSize(width: 1_440, height: 900)
            ),
            try PanelContentSize(width: 489.6, height: 630)
        )
        XCTAssertEqual(
            BuiltInPanelSizePreset.comfortable.contentSize(
                forScreenSize: CGSize(width: 2_560, height: 1_440)
            ),
            try PanelContentSize(width: 560, height: 720)
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
                name: "COMPACT",
                contentSize: PanelContentSize(width: 420, height: 520)
            )
        ) {
            XCTAssertEqual(
                $0 as? PanelSizePreferencesError,
                .duplicateName("COMPACT")
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

        try preferences.setDefaultPreset(id: .wide)
        XCTAssertEqual(preferences.defaultPresetID, .wide)
        XCTAssertEqual(preferences.defaultPreset, .builtIn(.wide))

        try preferences.setDefaultPreset(id: .custom(custom.id))
        XCTAssertEqual(preferences.defaultPresetID, .custom(custom.id))
        XCTAssertEqual(preferences.defaultPreset, .custom(custom))
    }

    func testDeletingDefaultCustomPresetFallsBackToComfortable() throws {
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

        XCTAssertEqual(preferences.defaultPresetID, .comfortable)
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
        XCTAssertEqual(preferences.defaultPresetID, .comfortable)
    }

    func testPresetIdentifiersUseStableCodableStrings() throws {
        let customID = UUID(uuidString: "C087FAE9-31D0-40A8-A3DD-5C876AB9CB18")!
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(
            String(data: try encoder.encode(PanelSizePresetID.wide), encoding: .utf8),
            "\"builtin:wide\""
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
