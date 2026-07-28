import XCTest
@testable import NotionPiP

@MainActor
final class PiPChromeViewTests: XCTestCase {
    func testOpenInNotionAndStashOpensActivePageBeforeStashing() throws {
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef")
            )
        )
        var openedURLs: [URL] = []
        var stashCount = 0
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        session.activate(page: page)
        let chrome = PiPChromeView(
            webSession: session,
            onStash: {
                XCTAssertEqual(openedURLs, [page.canonicalURL])
                stashCount += 1
            }
        )

        chrome.openInNotionAndStash()

        XCTAssertEqual(stashCount, 1)
    }

    func testRepinActionInvokesProvidedRecoveryHandler() {
        var invocationCount = 0
        let chrome = PiPChromeView(
            webSession: NotionWebSession(),
            onReloadSavedPin: { invocationCount += 1 }
        )

        chrome.repinCurrentPage()

        XCTAssertEqual(invocationCount, 1)
    }
}
