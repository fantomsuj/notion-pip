import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class NotionWebSessionTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testActivateDeduplicatesSamePageAndPublishesLoadingState() throws {
        let session = NotionWebSession()
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.activate(page: page)

        XCTAssertEqual(session.activePage?.pageID, firstPageID)
        XCTAssertEqual(session.state, .loading)
    }

    func testActivateReplacesTheActivePage() throws {
        let session = NotionWebSession()
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        session.activate(page: firstPage)
        session.activate(page: secondPage)

        XCTAssertEqual(session.activePage?.pageID, secondPageID)
        XCTAssertEqual(session.webView.url, secondPage.canonicalURL)
    }

    func testNavigationDelegatePublishesReadyAndFailureStates() throws {
        let session = NotionWebSession()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)

        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(session.webView, didFinish: nil)
        XCTAssertEqual(session.state, .ready)

        navigationDelegate.webView?(
            session.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline"])
        )
        XCTAssertEqual(session.state, .failed("Offline"))
    }

    func testOpenInBrowserUsesTheActivePageURL() throws {
        var openedURLs: [URL] = []
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.openInBrowser()

        XCTAssertEqual(openedURLs, [page.canonicalURL])
    }

    func testFailureStateShowsGenericMessageAndRetryWithoutExposingWebKitErrorText() throws {
        let session = NotionWebSession()
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(
            session.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: "Test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Request to https://www.notion.so/?token=secret failed"]
            )
        )
        let chrome = PiPChromeView(
            webSession: session,
            nativePageDocument: NativePageDocument(),
            onHide: {}
        )
        let presentation = String(reflecting: chrome.body)

        XCTAssertTrue(presentation.contains("Notion couldn't load this page."))
        XCTAssertTrue(presentation.contains("Try Again"))
        XCTAssertFalse(presentation.contains("secret"))
    }

    func testPiPChromeExposesAccessibleStashAction() {
        let chrome = PiPChromeView(
            webSession: NotionWebSession(),
            nativePageDocument: NativePageDocument(),
            onStash: {},
            onHide: {}
        )

        _ = chrome.body

        XCTAssertEqual(PiPChromeView.stashAccessibilityLabel, "Stash Notion PiP to Side")
        XCTAssertEqual(
            PiPChromeView.stashHelp,
            "Move the Notion PiP to the nearest screen edge"
        )
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }
}
