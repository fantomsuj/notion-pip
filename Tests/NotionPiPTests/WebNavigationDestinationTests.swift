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
    func testNotionSessionAllowsTrustedNavigationAndOpensExternalOnce() throws {
        var openedURLs: [URL] = []
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        let trustedURL = try XCTUnwrap(URL(string: "https://notion.so/workspace"))
        let externalURL = try XCTUnwrap(URL(string: "https://example.com/path"))

        XCTAssertEqual(
            session.navigationPolicy(for: trustedURL, targetFrameIsPresent: true),
            .allow
        )
        XCTAssertEqual(
            session.navigationPolicy(for: externalURL, targetFrameIsPresent: true),
            .cancel
        )
        XCTAssertEqual(
            session.navigationPolicy(for: nil, targetFrameIsPresent: true),
            .cancel
        )
        XCTAssertEqual(openedURLs, [externalURL])
    }

    @MainActor
    func testNewWindowTrustedRequestDefersThenLoadsExistingWebViewAndReturnsNil() throws {
        var loadedRequests: [URLRequest] = []
        let webView = WKWebView()
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { loadedWebView, request in
                XCTAssertTrue(loadedWebView === webView)
                loadedRequests.append(request)
            }
        )
        let request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://www.notion.so/workspace"))
        )

        XCTAssertEqual(
            session.navigationPolicy(for: request.url, targetFrameIsPresent: false),
            .allow
        )
        XCTAssertTrue(loadedRequests.isEmpty)
        XCTAssertNil(session.handleNewWindowRequest(request, in: webView))
        XCTAssertEqual(loadedRequests, [request])
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
            session.navigationPolicy(for: externalURL, targetFrameIsPresent: false),
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
            session.navigationPolicy(for: unsupportedURL, targetFrameIsPresent: false),
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
