import Foundation
import XCTest
@testable import NotionPiP

final class NativePageSnapshotTests: XCTestCase {
    func testSnapshotRemainsCodableForExistingCachedPreviews() throws {
        let snapshot = NativePageSnapshot(
            pageID: "page-1",
            title: "Project brief",
            blocks: [],
            remoteFingerprint: "2026-07-21T10:00:00Z",
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(try JSONDecoder().decode(NativePageSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }
}
