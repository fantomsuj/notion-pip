import Foundation
import XCTest
@testable import NotionPiP

final class ExternalURLRouteTests: XCTestCase {
    private let pageID = "0123456789abcdef0123456789abcdef"

    func testPercentEncodedPageURLParsesPinRoute() throws {
        let routeURL = try XCTUnwrap(
            URL(
                string: "notion-pip://pin?url=https%3A%2F%2Fnotion.com%2FProject-\(pageID)%3Fview%3Dall%23notes&source=chrome-extension"
            )
        )

        let result = ExternalURLRoute.parse(routeURL)

        guard case let .success(.pin(page, source)) = result else {
            return XCTFail("Expected a pin route, got \(result)")
        }
        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(page.canonicalURL.absoluteString, "https://www.notion.com/Project-\(pageID)")
        XCTAssertEqual(source, .chromeExtension)
    }

    func testAppHostPageURLParsesPinRouteWithoutChangingHost() throws {
        var components = exactRouteComponents()
        components.queryItems = [
            URLQueryItem(
                name: "url",
                value: "https://app.notion.com/p/acme/Project-\(pageID)?view=all#notes"
            ),
            URLQueryItem(name: "source", value: "chrome-extension"),
        ]
        let routeURL = try XCTUnwrap(components.url)

        let result = ExternalURLRoute.parse(routeURL)

        guard case let .success(.pin(page, source)) = result else {
            return XCTFail("Expected a pin route, got \(result)")
        }
        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://app.notion.com/p/acme/Project-\(pageID)"
        )
        XCTAssertEqual(source, .chromeExtension)
    }

    func testWWWWorkspacePageURLParsesPinRouteWithoutDroppingWorkspacePath() throws {
        var components = exactRouteComponents()
        components.queryItems = [
            URLQueryItem(
                name: "url",
                value: "https://www.notion.com/acme/Project-\(pageID)?view=all#notes"
            ),
            URLQueryItem(name: "source", value: "chrome-extension"),
        ]
        let routeURL = try XCTUnwrap(components.url)

        let result = ExternalURLRoute.parse(routeURL)

        guard case let .success(.pin(page, source)) = result else {
            return XCTFail("Expected a pin route, got \(result)")
        }
        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/acme/Project-\(pageID)"
        )
        XCTAssertEqual(source, .chromeExtension)
    }

    func testUnknownActionIsRejected() throws {
        let routeURL = try route(action: "open", source: "chrome-extension")

        XCTAssertEqual(ExternalURLRoute.parse(routeURL), .failure(.unknownAction("open")))
    }

    func testUnknownSourceIsRejected() throws {
        let routeURL = try route(action: "pin", source: "untrusted-client")

        XCTAssertEqual(
            ExternalURLRoute.parse(routeURL),
            .failure(.unknownSource("untrusted-client"))
        )
    }

    func testWrongSchemeIsRejected() throws {
        let routeURL = try XCTUnwrap(
            URL(string: "https://pin?url=https%3A%2F%2Fwww.notion.so%2F\(pageID)&source=chrome-extension")
        )

        XCTAssertEqual(ExternalURLRoute.parse(routeURL), .failure(.unsupportedScheme))
    }

    func testUserInfoIsRejected() throws {
        var components = exactRouteComponents()
        components.user = "user"
        components.password = "password"

        try assertRejected(XCTUnwrap(components.url))
    }

    func testPortIsRejected() throws {
        var components = exactRouteComponents()
        components.port = 8_443

        try assertRejected(XCTUnwrap(components.url))
    }

    func testFragmentIsRejected() throws {
        var components = exactRouteComponents()
        components.fragment = "ignored"

        try assertRejected(XCTUnwrap(components.url))
    }

    func testRootPathIsRejected() throws {
        var components = exactRouteComponents()
        components.path = "/"

        try assertRejected(XCTUnwrap(components.url))
    }

    func testUnknownQueryItemIsRejected() throws {
        var components = exactRouteComponents()
        components.queryItems?.append(URLQueryItem(name: "trace", value: "untrusted"))

        try assertRejected(XCTUnwrap(components.url))
    }

    func testNilValuedDuplicateURLItemIsRejected() throws {
        var components = exactRouteComponents()
        components.queryItems?.append(URLQueryItem(name: "url", value: nil))

        try assertRejected(XCTUnwrap(components.url))
    }

    func testNilValuedDuplicateSourceItemIsRejected() throws {
        var components = exactRouteComponents()
        components.queryItems?.append(URLQueryItem(name: "source", value: nil))

        try assertRejected(XCTUnwrap(components.url))
    }

    func testMissingURLAndSourceAreRejected() throws {
        let missingURL = try XCTUnwrap(URL(string: "notion-pip://pin?source=chrome-extension"))
        let missingSource = try XCTUnwrap(
            URL(string: "notion-pip://pin?url=https%3A%2F%2Fwww.notion.so%2F\(pageID)")
        )

        XCTAssertEqual(ExternalURLRoute.parse(missingURL), .failure(.missingPageURL))
        XCTAssertEqual(ExternalURLRoute.parse(missingSource), .failure(.missingSource))
    }

    func testInvalidNestedPageURLIsRejected() throws {
        let routeURL = try XCTUnwrap(
            URL(string: "notion-pip://pin?url=http%3A%2F%2Fwww.notion.so%2F\(pageID)&source=chrome-extension")
        )

        XCTAssertEqual(
            ExternalURLRoute.parse(routeURL),
            .failure(.invalidPage(.unsupportedScheme))
        )
    }

    func testOversizedProtocolURLIsRejectedBeforeParsingValues() throws {
        let oversizedSource = String(repeating: "a", count: 8_192)
        let routeURL = try route(action: "pin", source: oversizedSource)

        XCTAssertEqual(ExternalURLRoute.parse(routeURL), .failure(.inputTooLong))
    }

    private func route(action: String, source: String) throws -> URL {
        var components = exactRouteComponents()
        components.host = action
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.notion.so/\(pageID)"),
            URLQueryItem(name: "source", value: source),
        ]
        return try XCTUnwrap(components.url)
    }

    private func exactRouteComponents() -> URLComponents {
        var components = URLComponents()
        components.scheme = "notion-pip"
        components.host = "pin"
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://www.notion.so/\(pageID)"),
            URLQueryItem(name: "source", value: "chrome-extension"),
        ]
        return components
    }

    private func assertRejected(
        _ routeURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure = ExternalURLRoute.parse(routeURL) else {
            return XCTFail("Expected route to be rejected: \(routeURL)", file: file, line: line)
        }
    }
}
