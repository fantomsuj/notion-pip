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

    func testTopControlsAppearOnlyAfterPointerRemainsAtTopEdge() async throws {
        let controller = TopControlsHoverController(revealDelay: .milliseconds(30))

        controller.setHovering(true)

        XCTAssertFalse(controller.isHovering)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(controller.isHovering)
    }

    func testTopControlsHoverSurfaceExtendsBeyondVisibleToolbar() {
        XCTAssertEqual(PiPChromeView.topControlsHoverOutset, 12)
        XCTAssertEqual(PiPChromeView.topControlsRevealHeight, 8)
    }

    func testTopControlsDoNotAppearWhenPointerLeavesBeforeRevealDelay() async throws {
        let controller = TopControlsHoverController(revealDelay: .milliseconds(30))

        controller.setHovering(true)
        try await Task.sleep(for: .milliseconds(10))
        controller.setHovering(false)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertFalse(controller.isHovering)
    }

    func testTopControlsDismissShortlyAfterPointerLeaves() async throws {
        let controller = TopControlsHoverController(
            revealDelay: .milliseconds(10),
            dismissalDelay: .milliseconds(10)
        )

        controller.setHovering(true)
        try await Task.sleep(for: .milliseconds(20))
        controller.setHovering(false)

        try await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(controller.isHovering)
    }

    func testTopControlsStayVisibleWhenPointerReentersBeforeDismissal() async throws {
        let controller = TopControlsHoverController(
            revealDelay: .milliseconds(10),
            dismissalDelay: .milliseconds(30)
        )

        controller.setHovering(true)
        try await Task.sleep(for: .milliseconds(20))
        controller.setHovering(false)
        try await Task.sleep(for: .milliseconds(10))
        controller.setHovering(true)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertTrue(controller.isHovering)
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

    func testOfflineModeAutomaticallyOpensDurableQuickCapture() throws {
        var quickCaptureCount = 0
        let commandModel = AppCommandModel(
            quickCapture: { quickCaptureCount += 1 },
            settings: {},
            quit: {}
        )
        let session = NotionWebSession()
        session.activate(
            page: try NotionPageReference(
                validating: XCTUnwrap(
                    URL(string: "https://www.notion.so/Offline-0123456789abcdef0123456789abcdef")
                )
            )
        )
        let webView = try XCTUnwrap(session.webView)
        session.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )
        )
        let chrome = PiPChromeView(webSession: session, commandModel: commandModel)

        chrome.enterOfflineCaptureMode()

        XCTAssertEqual(quickCaptureCount, 1)
    }
}
