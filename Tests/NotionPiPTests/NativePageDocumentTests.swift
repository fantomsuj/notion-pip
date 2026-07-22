import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class NativePageDocumentTests: XCTestCase {
    func testLoadedPreviewRemainsCachedWithoutEditableState() {
        let document = NativePageDocument()
        document.load(
            NativePageSnapshot(
                pageID: "page-1",
                title: "Brief",
                blocks: [NativePageBlock(id: "block-1", kind: .paragraph, text: "Before")],
                remoteFingerprint: "fingerprint",
                fetchedAt: Date()
            )
        )

        XCTAssertEqual(document.snapshot?.blocks.first?.text, "Before")
        XCTAssertEqual(document.previewState, .cached)
    }
}
