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

    private func makeGeometry() throws -> PanelGeometry {
        try PanelGeometry(
            desiredContentSize: PanelContentSize(width: 760, height: 520),
            frame: CGRect(x: 656, y: 356, width: 760, height: 520),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            anchor: PanelFrameAnchor(
                horizontalEdge: .right,
                horizontalInset: 24,
                verticalEdge: .top,
                verticalInset: 24
            )
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
