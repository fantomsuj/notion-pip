import Foundation
import XCTest
@testable import NotionPiP

final class PersistenceConfigurationTests: XCTestCase {
    func testDefaultContainerUsesAppSpecificStoreWithoutTouchingGenericDefaultStore() throws {
        let applicationSupportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: applicationSupportDirectory) }

        let genericStoreURL = applicationSupportDirectory.appendingPathComponent("default.store")
        let unrelatedStoreContents = Data("unrelated-store".utf8)
        try unrelatedStoreContents.write(to: genericStoreURL)

        let container = try NotionPiPPersistence.makeContainer(
            applicationSupportDirectory: applicationSupportDirectory
        )
        withExtendedLifetime(container) {
            let appStoreURL = applicationSupportDirectory
                .appendingPathComponent("com.fantomsuj.NotionPiP", isDirectory: true)
                .appendingPathComponent("NotionPiP.store")

            XCTAssertTrue(FileManager.default.fileExists(atPath: appStoreURL.path))
            XCTAssertEqual(try? Data(contentsOf: genericStoreURL), unrelatedStoreContents)
        }
    }
}
