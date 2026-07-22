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

    func testCreateNewPageLoadsFixedRouteOnceUntilNavigationCompletes() {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in
            requests.append(request)
        })

        session.createNewPage()
        session.createNewPage()

        XCTAssertEqual(requests.map(\.url?.absoluteString), ["https://www.notion.so/new"])
        XCTAssertTrue(session.isCreatingNewPage)
        XCTAssertEqual(session.state, .loading)
    }

    func testFailedCreationAllowsAnotherAttempt() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in
            requests.append(request)
        })
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.createNewPage()

        navigationDelegate.webView?(
            session.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "Test", code: 1)
        )
        session.createNewPage()

        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(session.isCreatingNewPage)
    }

    func testURLChangeReportsNewCanonicalPageOnceAcrossNavigationCompletion() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.webView.load(
            URLRequest(
                url: try XCTUnwrap(
                    URL(string: "https://www.notion.so/New-Page-\(secondPageID)?pvs=4")
                )
            )
        )
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        XCTAssertEqual(resolvedPages.map(\.pageID), [secondPageID])
        XCTAssertEqual(session.activePage?.pageID, secondPageID)

        navigationDelegate.webView?(session.webView, didFinish: nil)
        navigationDelegate.webView?(session.webView, didFinish: nil)

        XCTAssertEqual(resolvedPages.map(\.pageID), [secondPageID])
        XCTAssertEqual(session.activePage?.pageID, secondPageID)
        XCTAssertFalse(session.isCreatingNewPage)
    }

    func testFinishedIntermediateNavigationDoesNotReplaceActivePage() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        let original = try makePage(id: firstPageID, title: "Roadmap")
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: original)
        session.webView.load(
            URLRequest(url: try XCTUnwrap(URL(string: "https://www.notion.so/new")))
        )
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        navigationDelegate.webView?(session.webView, didFinish: nil)

        XCTAssertTrue(resolvedPages.isEmpty)
        XCTAssertEqual(session.activePage, original)
    }

    func testEditorActivityBridgeAcceptsOnlyMainFrameNotionHTTPSMessages() {
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            ),
            .typingStarted
        )
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "editingEnded",
                isMainFrame: true,
                scheme: "https",
                host: "notion.so"
            ),
            .editingEnded
        )

        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: false,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "http",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "https",
                host: "notion.example"
            )
        )
        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: ["activity": "typingStarted"],
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
    }

    func testTypingActivityHidesTopControlsUntilEditingEnds() {
        let session = NotionWebSession()
        let chrome = PiPChromeView(
            webSession: session,
            nativePageDocument: NativePageDocument()
        )

        XCTAssertFalse(session.isTypingInPage)
        XCTAssertTrue(chrome.showsTopControls)

        session.handleEditorActivity(.typingStarted)

        XCTAssertTrue(session.isTypingInPage)
        XCTAssertFalse(chrome.showsTopControls)

        session.handleEditorActivity(.editingEnded)

        XCTAssertFalse(session.isTypingInPage)
        XCTAssertTrue(chrome.showsTopControls)
    }

    func testVoiceOverKeepsTopControlsVisibleWhileTyping() {
        XCTAssertFalse(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: true,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: true,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: true
            )
        )
    }

    func testEditorActivityScriptRunsAtDocumentStartInMainFrameOnly() throws {
        let session = NotionWebSession()
        let script = try XCTUnwrap(
            session.webView.configuration.userContentController.userScripts.first
        )

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertTrue(script.isForMainFrameOnly)
        XCTAssertTrue(script.source.contains("beforeinput"))
        XCTAssertTrue(script.source.contains("pointermove"))
        XCTAssertTrue(script.source.contains("focusout"))
        XCTAssertTrue(
            script.source.contains(
                "if (editableElement(event.target)) publishTypingStarted();"
            )
        )
    }

    func testNavigationResetsTypingActivity() throws {
        let session = NotionWebSession()
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.handleEditorActivity(.typingStarted)

        navigationDelegate.webView?(session.webView, didStartProvisionalNavigation: nil)

        XCTAssertFalse(session.isTypingInPage)
    }

    func testAdoptingResolvedSPAPageResetsTypingActivity() throws {
        let session = NotionWebSession()
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.handleEditorActivity(.typingStarted)

        session.adoptResolvedPage(
            at: try XCTUnwrap(URL(string: "https://www.notion.so/Notes-\(secondPageID)"))
        )

        XCTAssertFalse(session.isTypingInPage)
        XCTAssertEqual(session.activePage?.pageID, secondPageID)
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
            nativePageDocument: NativePageDocument()
        )
        let presentation = String(reflecting: chrome.body)

        XCTAssertTrue(presentation.contains("Notion couldn't load this page."))
        XCTAssertTrue(presentation.contains("Try Again"))
        XCTAssertFalse(presentation.contains("secret"))
    }

    func testPiPChromeExposesAccessibleToolbarActionsWithoutRedundantHideAction() {
        let chrome = PiPChromeView(
            webSession: NotionWebSession(),
            nativePageDocument: NativePageDocument(),
            onStash: {}
        )

        _ = chrome.body

        XCTAssertEqual(PiPChromeView.newPageAccessibilityLabel, "Create New Notion Page")
        XCTAssertEqual(PiPChromeView.newPageHelp, "Create a new page in Notion")
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
