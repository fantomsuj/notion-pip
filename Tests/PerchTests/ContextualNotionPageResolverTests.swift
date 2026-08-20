import Foundation
import XCTest
@testable import Perch

final class ContextualNotionPageResolverTests: XCTestCase {
    private let pageID = "0123456789abcdef0123456789abcdef"

    func testKnownBrowsersAcceptStrictHTTPSNotionPageURLs() throws {
        let fixtures = [
            ("com.apple.Safari", "https://www.notion.com/Roadmap-\(pageID)"),
            ("com.google.Chrome", "https://notion.so/Roadmap-\(pageID)?v=1"),
            ("org.mozilla.firefox", "https://app.notion.com/p/acme/Roadmap-\(pageID)#today"),
            ("com.microsoft.edgemac", "https://www.notion.so/Roadmap-\(pageID)"),
            ("com.brave.Browser", "https://notion.com/Roadmap-\(pageID)"),
            ("company.thebrowser.Browser", "https://www.notion.com/Roadmap-\(pageID)"),
        ]

        for (bundleIdentifier, rawURL) in fixtures {
            let page = try XCTUnwrap(
                ContextualNotionPageResolver.resolve(
                    rawURL: rawURL,
                    sourceBundleIdentifier: bundleIdentifier
                ),
                "Expected \(bundleIdentifier) to accept \(rawURL)"
            )

            XCTAssertEqual(page.pageID, pageID)
        }
    }

    func testNotionDesktopDeepLinkNormalizesBeforeStrictValidation() throws {
        let page = try XCTUnwrap(
            ContextualNotionPageResolver.resolve(
                rawURL: "notion://www.notion.so/acme/Roadmap-\(pageID)?v=1#today",
                sourceBundleIdentifier: "notion.id"
            )
        )

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(
            page.canonicalURL.absoluteString,
            "https://www.notion.com/acme/Roadmap-\(pageID)"
        )
    }

    func testBrowserRejectsLookalikeHostsUnsupportedSchemesMalformedURLsAndMissingPageIDs() {
        let rejected = [
            "https://notion.com.example.com/Roadmap-\(pageID)",
            "https://example.com/Roadmap-\(pageID)",
            "http://www.notion.com/Roadmap-\(pageID)",
            "notion://www.notion.so/Roadmap-\(pageID)",
            "file:///Roadmap-\(pageID)",
            "https://www.notion.com/%",
            "https://www.notion.com/search",
            "https://www.notion.com",
        ]

        for rawURL in rejected {
            XCTAssertNil(
                ContextualNotionPageResolver.resolve(
                    rawURL: rawURL,
                    sourceBundleIdentifier: "com.google.Chrome"
                ),
                "Expected strict browser rejection for \(rawURL)"
            )
        }
    }

    func testNotionDeepLinkRejectsLookalikeHostAndUnsupportedSource() {
        XCTAssertNil(
            ContextualNotionPageResolver.resolve(
                rawURL: "notion://www.notion.so.example.com/Roadmap-\(pageID)",
                sourceBundleIdentifier: "notion.id"
            )
        )
        XCTAssertNil(
            ContextualNotionPageResolver.resolve(
                rawURL: "notion://www.notion.so/Roadmap-\(pageID)",
                sourceBundleIdentifier: "com.google.Chrome"
            )
        )
        XCTAssertNil(
            ContextualNotionPageResolver.resolve(
                rawURL: "https://www.notion.com/Roadmap-\(pageID)",
                sourceBundleIdentifier: "com.tinyspeck.slackmacgap"
            )
        )
    }

    func testExactSnapshotUsesOnlyURLAttributeValues() throws {
        let source = ContextSourceIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )

        let snapshot = try XCTUnwrap(
            AccessibilityExactPageContextResolver.snapshot(
                source: source,
                urlAttributeValues: [
                    "https://example.com/Roadmap-\(pageID)",
                    "https://www.notion.com/Roadmap-\(pageID)",
                ]
            )
        )

        XCTAssertEqual(snapshot.source, source)
        XCTAssertEqual(snapshot.exactPage?.pageID, pageID)
        XCTAssertNil(snapshot.windowTitle)
        XCTAssertNil(snapshot.documentURL)
    }

    func testExactSnapshotDoesNotInferPageFromAbsentURLAttributes() {
        let source = ContextSourceIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )

        XCTAssertNil(
            AccessibilityExactPageContextResolver.snapshot(
                source: source,
                urlAttributeValues: []
            )
        )
    }

    func testExactCaptureRejectsTerminatedMissingAndReusedSourceProcesses() {
        let source = ContextSourceIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )

        XCTAssertFalse(
            AccessibilityContextSourceValidation.acceptsResult(
                source: source,
                runningProcessIdentifier: 42,
                runningBundleIdentifier: "com.apple.Safari",
                isTerminated: true
            )
        )
        XCTAssertFalse(
            AccessibilityContextSourceValidation.acceptsResult(
                source: source,
                runningProcessIdentifier: nil,
                runningBundleIdentifier: nil,
                isTerminated: false
            )
        )
        XCTAssertFalse(
            AccessibilityContextSourceValidation.acceptsResult(
                source: source,
                runningProcessIdentifier: 42,
                runningBundleIdentifier: "com.google.Chrome",
                isTerminated: false
            )
        )
        XCTAssertTrue(
            AccessibilityContextSourceValidation.acceptsResult(
                source: source,
                runningProcessIdentifier: 42,
                runningBundleIdentifier: "com.apple.Safari",
                isTerminated: false
            )
        )
    }
}
