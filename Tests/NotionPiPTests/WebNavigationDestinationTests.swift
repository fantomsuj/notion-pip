import Foundation
import WebKit
import XCTest
@testable import NotionPiP

final class WebNavigationDestinationTests: XCTestCase {
    func testClassifiesEveryExactNotionHostAsTrusted() throws {
        for host in [
            "app.notion.com",
            "notion.com",
            "www.notion.com",
            "notion.so",
            "www.notion.so",
        ] {
            XCTAssertEqual(
                WebNavigationDestination.classify(
                    try XCTUnwrap(URL(string: "https://\(host)/workspace"))
                ),
                .trustedNotion
            )
        }
    }

    func testNormalizesTrustedNotionHostCase() throws {
        XCTAssertEqual(
            WebNavigationDestination.classify(
                try XCTUnwrap(URL(string: "https://APP.NOTION.COM/workspace"))
            ),
            .trustedNotion
        )
    }

    func testClassifiesExactNotionIdentityHostAsTrusted() throws {
        XCTAssertEqual(
            WebNavigationDestination.classify(
                try XCTUnwrap(URL(string: "https://identity.notion.com/authSync"))
            ),
            .trustedNotion
        )
    }

    func testClassifiesHTTPNotionAndNonNotionWebURLsAsExternal() throws {
        for rawURL in [
            "http://app.notion.com/workspace",
            "http://example.com/path",
            "https://example.com/path",
        ] {
            XCTAssertEqual(
                WebNavigationDestination.classify(try XCTUnwrap(URL(string: rawURL))),
                .externalWeb
            )
        }
    }

    func testRejectsCredentialBearingWebURLs() throws {
        for rawURL in [
            "https://user@app.notion.com/workspace",
            "https://user:password@example.com/path",
            "https://:password@www.notion.com/workspace",
        ] {
            XCTAssertEqual(
                WebNavigationDestination.classify(try XCTUnwrap(URL(string: rawURL))),
                .unsupported
            )
        }
    }

    func testClassifiesLookalikeNotionHostsAsExternal() throws {
        for rawURL in [
            "https://notion.so.evil.example/workspace",
            "https://www.notion.so.evil.example/workspace",
            "https://evilnotion.so/workspace",
            "https://notion.com.evil.example/workspace",
            "https://www.notion.com.evil.example/workspace",
            "https://evilnotion.com/workspace",
        ] {
            XCTAssertEqual(
                WebNavigationDestination.classify(try XCTUnwrap(URL(string: rawURL))),
                .externalWeb
            )
        }
    }

    func testRejectsNilRelativeMalformedAndUnsupportedSchemes() throws {
        XCTAssertEqual(WebNavigationDestination.classify(nil), .unsupported)
        XCTAssertEqual(
            WebNavigationDestination.classify(try XCTUnwrap(URL(string: "../relative"))),
            .unsupported
        )
        XCTAssertNil(URL(string: "https://exa mple.com"))

        for rawURL in [
            "https:missing-host",
            "file:///tmp/index.html",
            "data:text/plain,hello",
            "javascript:alert(1)",
            "notion://workspace",
            "ftp://example.com/file",
        ] {
            XCTAssertEqual(
                WebNavigationDestination.classify(try XCTUnwrap(URL(string: rawURL))),
                .unsupported
            )
        }
    }

    @MainActor
    func testNotionSessionAllowsTrustedNavigationAndOpensExternalOnce() throws {
        var openedURLs: [URL] = []
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        let trustedURL = try XCTUnwrap(URL(string: "https://notion.com/workspace"))
        let externalURL = try XCTUnwrap(URL(string: "https://example.com/path"))

        XCTAssertEqual(
            session.navigationPolicy(for: trustedURL, context: .mainFrame),
            .allow
        )
        XCTAssertEqual(
            session.navigationPolicy(for: externalURL, context: .mainFrame),
            .cancel
        )
        XCTAssertEqual(
            session.navigationPolicy(for: nil, context: .mainFrame),
            .cancel
        )
        XCTAssertEqual(openedURLs, [externalURL])
    }

    @MainActor
    func testAllowsExternalHTTPSSubframeWithoutOpeningBrowser() throws {
        var openedURLs: [URL] = []
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        let analyticsURL = try XCTUnwrap(
            URL(string: "https://aif.notion.so/aif-production.html")
        )

        XCTAssertEqual(
            session.navigationPolicy(for: analyticsURL, context: .subframe),
            .allow
        )
        XCTAssertTrue(openedURLs.isEmpty)
    }

    func testTrustedNewWindowProducesPopupDecision() throws {
        let request = URLRequest(
            url: try XCTUnwrap(
                URL(string: "https://app.notion.com/verifyNoPopupBlockerHtmlAndRedirect")
            )
        )

        XCTAssertEqual(
            NotionWebNavigationPolicy().newWindowDecision(for: request),
            .createPopup
        )
    }

    @MainActor
    func testTrustedNewWindowReturnsPopupWithoutReplacingMainWebView() throws {
        let mainWebView = WKWebView()
        let popupWebView = WKWebView()
        let popupCoordinator = PopupCoordinatorSpy(webView: popupWebView)
        var mainLoads: [URLRequest] = []
        let session = NotionWebSession(
            webView: mainWebView,
            loadRequest: { _, request in mainLoads.append(request) },
            popupCoordinator: popupCoordinator
        )
        let configuration = WKWebViewConfiguration()
        let request = URLRequest(
            url: try XCTUnwrap(
                URL(string: "https://app.notion.com/verifyNoPopupBlockerHtmlAndRedirect")
            )
        )

        let returned = session.handleNewWindowRequest(
            request,
            configuration: configuration,
            in: mainWebView
        )

        XCTAssertTrue(returned === popupWebView)
        XCTAssertTrue(popupCoordinator.receivedConfiguration === configuration)
        XCTAssertTrue(mainLoads.isEmpty)
        XCTAssertTrue(session.webView === mainWebView)
    }

    @MainActor
    func testRendererTerminationClosesActivePopup() {
        let mainWebView = WKWebView()
        let popupCoordinator = PopupCoordinatorSpy(webView: WKWebView())
        let session = NotionWebSession(
            webView: mainWebView,
            popupCoordinator: popupCoordinator
        )

        session.webViewWebContentProcessDidTerminate(mainWebView)

        XCTAssertEqual(popupCoordinator.closeCallCount, 1)
    }

    @MainActor
    func testNewWindowExternalRequestDefersThenOpensOnceAndReturnsNil() throws {
        var openedURLs: [URL] = []
        var loadedRequests: [URLRequest] = []
        let webView = WKWebView()
        let session = NotionWebSession(
            webView: webView,
            openURL: { openedURLs.append($0) },
            loadRequest: { _, request in loadedRequests.append(request) }
        )
        let externalURL = try XCTUnwrap(URL(string: "http://example.com/path"))

        XCTAssertEqual(
            session.navigationPolicy(for: externalURL, context: .newWindow),
            .allow
        )
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(
            session.handleNewWindowRequest(
                URLRequest(url: externalURL),
                configuration: WKWebViewConfiguration(),
                in: webView
            )
        )
        XCTAssertEqual(openedURLs, [externalURL])
        XCTAssertTrue(loadedRequests.isEmpty)
    }

    @MainActor
    func testNewWindowUnsupportedRequestDefersThenDoesNothingAndReturnsNil() throws {
        var openedURLs: [URL] = []
        var loadedRequests: [URLRequest] = []
        let webView = WKWebView()
        let session = NotionWebSession(
            webView: webView,
            openURL: { openedURLs.append($0) },
            loadRequest: { _, request in loadedRequests.append(request) }
        )
        let unsupportedURL = try XCTUnwrap(URL(string: "javascript:alert(1)"))

        XCTAssertEqual(
            session.navigationPolicy(for: unsupportedURL, context: .newWindow),
            .allow
        )
        XCTAssertNil(
            session.handleNewWindowRequest(
                URLRequest(url: unsupportedURL),
                configuration: WKWebViewConfiguration(),
                in: webView
            )
        )
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertTrue(loadedRequests.isEmpty)
    }
}

@MainActor
private final class PopupCoordinatorSpy: NotionWebPopupCoordinating {
    let webView: WKWebView
    private(set) var receivedConfiguration: WKWebViewConfiguration?
    private(set) var closeCallCount = 0

    init(webView: WKWebView) {
        self.webView = webView
    }

    func present(using configuration: WKWebViewConfiguration) -> WKWebView {
        receivedConfiguration = configuration
        return webView
    }

    func close() {
        closeCallCount += 1
    }
}
