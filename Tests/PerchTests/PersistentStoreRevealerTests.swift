import Foundation
import XCTest
@testable import Perch

final class PersistentStoreRevealerTests: XCTestCase {
    func testRevealSelectsContainingDirectoryWhenPrimaryStoreIsMissing() {
        let storeDirectory = URL(fileURLWithPath: "/tmp/Perch", isDirectory: true)
        var revealedURLs: [[URL]] = []
        let revealer = PersistentStoreRevealer(
            storeDirectory: storeDirectory,
            fileExists: { _ in false },
            reveal: { revealedURLs.append($0) }
        )

        revealer.revealStore()

        XCTAssertEqual(revealedURLs, [[storeDirectory]])
    }

    func testRevealSelectsPrimaryStoreWhenItExists() {
        let storeDirectory = URL(fileURLWithPath: "/tmp/Perch", isDirectory: true)
        let storeURL = storeDirectory.appendingPathComponent("Perch.store")
        var revealedURLs: [[URL]] = []
        let revealer = PersistentStoreRevealer(
            storeDirectory: storeDirectory,
            fileExists: { $0 == storeURL },
            reveal: { revealedURLs.append($0) }
        )

        revealer.revealStore()

        XCTAssertEqual(revealedURLs, [[storeURL]])
    }
}
