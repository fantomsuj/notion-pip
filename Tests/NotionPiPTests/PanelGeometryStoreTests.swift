import CoreGraphics
import Foundation
import XCTest

@testable import NotionPiP

@MainActor
final class PanelGeometryStoreTests: XCTestCase {
    func testRoundTripPersistsUnifiedGeometry() throws {
        let defaults = try makeDefaults()
        let store = PanelGeometryStore(defaults: defaults)
        let geometry = try makeGeometry()

        try store.save(geometry)

        XCTAssertEqual(store.load(), geometry)
    }

    func testMissingGeometryReturnsNil() throws {
        let store = PanelGeometryStore(defaults: try makeDefaults())

        XCTAssertNil(store.load())
    }

    func testCorruptGeometryReturnsNil() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: PanelGeometryStore.key)
        let store = PanelGeometryStore(defaults: defaults)

        XCTAssertNil(store.load())
    }

    func testRoundTripPersistsDisplayAffinity() throws {
        let defaults = try makeDefaults()
        let store = PanelGeometryStore(defaults: defaults)
        let geometry = try makeGeometry(
            displayAffinity: DisplayAffinity(
                identifier: 22,
                visibleSize: CGSize(width: 1_920, height: 1_055),
                backingScaleFactor: 2,
                isPrimary: false,
                placement: .right
            )
        )

        try store.save(geometry)

        XCTAssertEqual(store.load(), geometry)
    }

    func testVersionOneGeometryMigratesWithoutDisplayAffinity() throws {
        struct LegacyGeometry: Codable {
            let version: Int
            let desiredContentSize: PanelContentSize
            let frame: CGRect
            let visibleFrame: CGRect
            let anchor: PanelFrameAnchor
        }
        let payload = LegacyGeometry(
            version: 1,
            desiredContentSize: try PanelContentSize(width: 760, height: 520),
            frame: CGRect(x: 656, y: 356, width: 760, height: 520),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
        )
        let defaults = try makeDefaults()
        defaults.set(try JSONEncoder().encode(payload), forKey: PanelGeometryStore.key)
        let store = PanelGeometryStore(defaults: defaults)

        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(migrated.version, PanelGeometry.currentVersion)
        XCTAssertNil(migrated.displayAffinity)
    }

    private func makeGeometry(
        displayAffinity: DisplayAffinity? = nil
    ) throws -> PanelGeometry {
        try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 760, height: 520),
            frame: CGRect(x: 656, y: 356, width: 760, height: 520),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            ),
            displayAffinity: displayAffinity
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "PanelGeometryStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
