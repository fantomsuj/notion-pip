import Foundation
import XCTest
@testable import NotionPiP

final class NotionWebNavigationPolicyTests: XCTestCase {
    private let policy = NotionWebNavigationPolicy()

    func testNewWindowNavigationDefersEveryDestinationToUIDelegate() throws {
        for url in [
            try XCTUnwrap(URL(string: "https://www.notion.so/workspace")),
            try XCTUnwrap(URL(string: "https://example.com/path")),
            try XCTUnwrap(URL(string: "javascript:alert(1)")),
        ] {
            XCTAssertEqual(
                policy.actionDecision(for: url, context: .newWindow),
                .allow
            )
        }
    }

    func testMainFrameNavigationAllowsTrustedOpensExternalAndCancelsUnsupported() throws {
        let trustedURL = try XCTUnwrap(URL(string: "https://app.notion.com/workspace"))
        let externalURL = try XCTUnwrap(URL(string: "http://example.com/path"))

        XCTAssertEqual(
            policy.actionDecision(for: trustedURL, context: .mainFrame),
            .allow
        )
        XCTAssertEqual(
            policy.actionDecision(for: externalURL, context: .mainFrame),
            .openExternally(externalURL)
        )
        XCTAssertEqual(
            policy.actionDecision(for: nil, context: .mainFrame),
            .cancel
        )
    }

    func testSubframeNavigationAllowsHTTPAndHTTPSButCancelsUnsupported() throws {
        for url in [
            try XCTUnwrap(URL(string: "https://aif.notion.so/aif-production.html")),
            try XCTUnwrap(URL(string: "http://example.com/frame")),
        ] {
            XCTAssertEqual(
                policy.actionDecision(for: url, context: .subframe),
                .allow
            )
        }
        XCTAssertEqual(
            policy.actionDecision(
                for: try XCTUnwrap(URL(string: "javascript:alert(1)")),
                context: .subframe
            ),
            .cancel
        )
    }

    func testNewWindowDecisionCreatesTrustedPopupAndRoutesExternalURL() throws {
        let trustedRequest = URLRequest(
            url: try XCTUnwrap(URL(string: "https://www.notion.so/workspace")),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 17
        )
        let externalURL = try XCTUnwrap(URL(string: "https://example.com/path"))

        XCTAssertEqual(
            policy.newWindowDecision(for: trustedRequest),
            .createPopup
        )
        XCTAssertEqual(
            policy.newWindowDecision(for: URLRequest(url: externalURL)),
            .openExternally(externalURL)
        )
        XCTAssertEqual(
            policy.newWindowDecision(
                for: URLRequest(
                    url: try XCTUnwrap(URL(string: "javascript:alert(1)"))
                )
            ),
            .ignore
        )
    }

    func testFailureDecisionDistinguishesCancellationOfflineAndGenericFailure() {
        XCTAssertEqual(
            policy.failureDecision(
                for: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            ),
            .cancelled
        )

        for code in [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
        ] {
            XCTAssertEqual(
                policy.failureDecision(
                    for: NSError(domain: NSURLErrorDomain, code: code)
                ),
                .offline,
                "Expected URL error code \(code) to be treated as offline"
            )
        }

        XCTAssertEqual(
            policy.failureDecision(for: NSError(domain: "Test", code: 1)),
            .failed("Notion couldn't load this page.")
        )
    }
}
