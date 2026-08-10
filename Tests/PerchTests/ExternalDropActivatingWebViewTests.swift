import AppKit
import WebKit
import XCTest
@testable import Perch

@MainActor
final class ExternalDropActivatingWebViewTests: XCTestCase {
    func testExternalTextClassificationReadsPlainAndRichTextWithoutChangingPasteboard() {
        let plainTextPasteboard = makePasteboard()
        XCTAssertTrue(plainTextPasteboard.setString("Selected text", forType: .string))
        let plainTextChangeCount = plainTextPasteboard.changeCount

        XCTAssertTrue(ExternalTextDrop.hasReadableText(in: plainTextPasteboard))
        XCTAssertEqual(plainTextPasteboard.string(forType: .string), "Selected text")
        XCTAssertEqual(plainTextPasteboard.changeCount, plainTextChangeCount)

        let richTextPasteboard = makePasteboard()
        XCTAssertTrue(
            richTextPasteboard.writeObjects([
                NSAttributedString(string: "Formatted selected text")
            ])
        )
        let richTextChangeCount = richTextPasteboard.changeCount

        XCTAssertTrue(ExternalTextDrop.hasReadableText(in: richTextPasteboard))
        XCTAssertEqual(richTextPasteboard.changeCount, richTextChangeCount)
    }

    func testNonTextPasteboardDoesNotQualifyForExternalTextActivation() {
        let pasteboard = makePasteboard()
        XCTAssertTrue(pasteboard.setData(Data([0x01]), forType: .png))

        XCTAssertFalse(ExternalTextDrop.hasReadableText(in: pasteboard))
    }

    func testWebViewDescendantSourceIsAnInternalDrag() {
        let webView = WKWebView()
        let descendant = NSView()
        webView.addSubview(descendant)

        XCTAssertFalse(
            ExternalTextDrop.isExternalDraggingSource(descendant, relativeTo: webView)
        )
        XCTAssertFalse(
            ExternalTextDrop.isExternalDraggingSource(webView, relativeTo: webView)
        )
        XCTAssertTrue(
            ExternalTextDrop.isExternalDraggingSource(NSView(), relativeTo: webView)
        )
    }

    func testActivationOccursOnlyOnceForPreparedDragSequence() {
        let activation = ExternalTextDropActivation()
        var activations = 0
        var focusAttempts = 0

        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { activations += 1; return true },
            focusWebView: { focusAttempts += 1; return true }
        )
        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { activations += 1; return true },
            focusWebView: { focusAttempts += 1; return true }
        )

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(focusAttempts, 1)
        XCTAssertTrue(activation.didActivatePanel)
        XCTAssertTrue(activation.didPrepareCurrentDrag)
    }

    func testActivationRetriesWhenWebViewWasUnattachedOnEntry() {
        let activation = ExternalTextDropActivation()
        var activations = 0
        var focusAttempts = 0

        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { activations += 1; return false },
            focusWebView: { focusAttempts += 1; return true }
        )
        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { activations += 1; return true },
            focusWebView: { focusAttempts += 1; return true }
        )

        XCTAssertEqual(activations, 2)
        XCTAssertEqual(focusAttempts, 1)
        XCTAssertTrue(activation.didPrepareCurrentDrag)
    }

    func testFocusRetryDoesNotReactivatePanel() {
        let activation = ExternalTextDropActivation()
        var activations = 0
        var focusAttempts = 0

        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { activations += 1; return true },
            focusWebView: { focusAttempts += 1; return false }
        )
        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { activations += 1; return true },
            focusWebView: { focusAttempts += 1; return true }
        )

        XCTAssertEqual(activations, 1)
        XCTAssertEqual(focusAttempts, 2)
        XCTAssertTrue(activation.didPrepareCurrentDrag)
    }

    func testInternalDragDoesNotActivatePanel() {
        let activation = ExternalTextDropActivation()
        var preparations = 0

        activation.prepareIfNeeded(
            for: 42,
            isExternalText: false,
            activatePanel: { preparations += 1; return true },
            focusWebView: { preparations += 1; return true }
        )

        XCTAssertEqual(preparations, 0)
        XCTAssertFalse(activation.didPrepareCurrentDrag)
    }

    func testResetAllowsTheNextDragSequenceToActivate() {
        let activation = ExternalTextDropActivation()
        var preparations = 0

        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { preparations += 1; return true },
            focusWebView: { return true }
        )
        activation.reset()
        activation.prepareIfNeeded(
            for: 42,
            isExternalText: true,
            activatePanel: { preparations += 1; return true },
            focusWebView: { return true }
        )

        XCTAssertEqual(preparations, 2)
    }

    func testSessionFactoryUsesDropAwareWebViewWithExistingConfiguration() throws {
        let session = NotionWebSession(loadRequest: { _, _ in })
        let page = try NotionPageReference(
            validating: XCTUnwrap(
                URL(string: "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef")
            )
        )

        session.activate(page: page)

        let webView = try XCTUnwrap(session.webView)
        XCTAssertTrue(webView is ExternalDropActivatingWebView)
        XCTAssertTrue(webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertEqual(webView.configuration.preferences.inactiveSchedulingPolicy, .suspend)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("ExternalDropActivatingWebViewTests.\(UUID())"))
        pasteboard.clearContents()
        return pasteboard
    }

}
