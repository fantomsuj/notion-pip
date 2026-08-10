import Foundation
import XCTest
@testable import Perch

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

        let container = try PerchPersistence.makeContainer(
            applicationSupportDirectory: applicationSupportDirectory
        )
        withExtendedLifetime(container) {
            let appStoreURL = applicationSupportDirectory
                .appendingPathComponent("com.fantomsuj.Perch", isDirectory: true)
                .appendingPathComponent("Perch.store")

            XCTAssertTrue(FileManager.default.fileExists(atPath: appStoreURL.path))
            XCTAssertEqual(try? Data(contentsOf: genericStoreURL), unrelatedStoreContents)
        }
    }
}
