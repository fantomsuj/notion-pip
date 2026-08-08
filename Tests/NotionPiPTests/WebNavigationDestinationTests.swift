import Foundation
import WebKit
import XCTest
@testable import NotionPiP

final class WebNavigationDestinationTests: XCTestCase {
    func testClassifiesEveryExactNotionHostAsTrusted() throws {
        for host in ["app.notion.com", "notion.so", "www.notion.so"] {
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
            "https://:password@www.notion.so/workspace",
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
    func testQuickCaptureCancelsWebNavigationAndOpensEachSupportedWebURLOnce() throws {
        var openedURLs: [URL] = []
        let session = CaptureEditorSession(
            repository: try CaptureRepository(inMemory: true),
            openURL: { openedURLs.append($0) }
        )
        let trustedURL = try XCTUnwrap(URL(string: "https://app.notion.com/workspace"))
        let externalURL = try XCTUnwrap(URL(string: "http://example.com/path"))

        XCTAssertEqual(session.handleNavigation(to: trustedURL), .cancel)
        XCTAssertEqual(session.handleNavigation(to: externalURL), .cancel)
        XCTAssertEqual(
            session.handleNavigation(to: URL(string: "javascript:alert(1)")),
            .cancel
        )
        XCTAssertEqual(openedURLs, [trustedURL, externalURL])
    }

    @MainActor
    func testNotionSessionAllowsTrustedNavigationAndOpensExternalOnce() throws {
        var openedURLs: [URL] = []
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        let trustedURL = try XCTUnwrap(URL(string: "https://notion.so/workspace"))
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
            session.handleNewWindowRequest(URLRequest(url: externalURL), in: webView)
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
                in: webView
            )
        )
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertTrue(loadedRequests.isEmpty)
    }
}
