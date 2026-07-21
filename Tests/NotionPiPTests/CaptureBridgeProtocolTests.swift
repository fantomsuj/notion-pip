import Foundation
import XCTest
@testable import NotionPiP

final class CaptureBridgeProtocolTests: XCTestCase {
    private let localMainFrame = BridgeMessageContext(
        isMainFrame: true,
        originScheme: "file",
        originHost: "",
        sourceURL: URL(fileURLWithPath: "/app/QuickCapture/index.html"),
        allowedDocumentURL: URL(fileURLWithPath: "/app/QuickCapture/index.html")
    )

    func testDecodesAllowlistedChangedMessageAndCanonicalizesDocument() throws {
        let data = Data(#"{"version":1,"id":"request-1","type":"changed","snapshot":{"draftID":"draft-1","title":"Note","document":{"type":"doc","content":[{"type":"paragraph","attrs":{"z":2,"a":1}}]}},"expectedRevision":4}"#.utf8)

        let request = try CaptureBridgeProtocol.decode(data, context: localMainFrame)

        guard case let .changed(id, snapshot, expectedRevision) = request else {
            return XCTFail("Expected a changed request")
        }
        XCTAssertEqual(id, "request-1")
        XCTAssertEqual(expectedRevision, 4)
        XCTAssertEqual(snapshot.draftID, "draft-1")
        XCTAssertEqual(
            String(decoding: snapshot.document, as: UTF8.self),
            #"{"content":[{"attrs":{"a":1,"z":2},"type":"paragraph"}],"type":"doc"}"#
        )
    }

    func testRejectsMalformedOversizedUnknownAndCredentialShapedMessages() throws {
        let malformed = Data(#"{"version":1,"id":7,"type":"ready"}"#.utf8)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(malformed, context: localMainFrame))

        let oversized = Data(repeating: 0x20, count: CaptureBridgeProtocol.maximumMessageBytes + 1)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(oversized, context: localMainFrame)) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .messageTooLarge)
        }

        let unknownType = Data(#"{"version":1,"id":"request-2","type":"evaluate","script":"steal()"}"#.utf8)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(unknownType, context: localMainFrame)) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .unsupportedType("evaluate"))
        }

        let unknownField = Data(#"{"version":1,"id":"request-3","type":"ready","token":"secret"}"#.utf8)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(unknownField, context: localMainFrame)) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .unknownField("token"))
        }
    }

    func testRejectsNonMainFrameAndNonLocalOrigins() throws {
        let ready = Data(#"{"version":1,"id":"ready-1","type":"ready"}"#.utf8)

        XCTAssertThrowsError(
            try CaptureBridgeProtocol.decode(
                ready,
                context: BridgeMessageContext(
                    isMainFrame: false,
                    originScheme: "file",
                    originHost: "",
                    sourceURL: localMainFrame.sourceURL,
                    allowedDocumentURL: localMainFrame.allowedDocumentURL
                )
            )
        ) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .notMainFrame)
        }
        XCTAssertThrowsError(
            try CaptureBridgeProtocol.decode(
                ready,
                context: BridgeMessageContext(
                    isMainFrame: true,
                    originScheme: "https",
                    originHost: "example.com",
                    sourceURL: URL(string: "https://example.com")!,
                    allowedDocumentURL: localMainFrame.allowedDocumentURL
                )
            )
        ) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .untrustedOrigin)
        }
    }

    func testRejectsAnotherLocalFileDocumentOutsideTheBundledEditor() throws {
        let ready = Data(#"{"version":1,"id":"ready-1","type":"ready"}"#.utf8)
        let context = BridgeMessageContext(
            isMainFrame: true,
            originScheme: "file",
            originHost: "",
            sourceURL: URL(fileURLWithPath: "/tmp/untrusted/index.html"),
            allowedDocumentURL: localMainFrame.allowedDocumentURL
        )

        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(ready, context: context)) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .untrustedOrigin)
        }
    }

    func testNavigationPolicyKeepsEditorLocalAndExternalNotionLinksOutOfWebView() {
        let root = URL(fileURLWithPath: "/app/QuickCapture", isDirectory: true)

        XCTAssertEqual(
            CaptureEditorNavigationPolicy.decision(
                for: URL(fileURLWithPath: "/app/QuickCapture/editor.js"),
                resourceRoot: root
            ),
            .allow
        )
        XCTAssertEqual(
            CaptureEditorNavigationPolicy.decision(
                for: URL(fileURLWithPath: "/tmp/other.html"),
                resourceRoot: root
            ),
            .cancel
        )
        XCTAssertEqual(
            CaptureEditorNavigationPolicy.decision(
                for: URL(string: "https://www.notion.so/example")!,
                resourceRoot: root
            ),
            .openExternal
        )
        XCTAssertEqual(
            CaptureEditorNavigationPolicy.decision(
                for: URL(string: "https://evil.example/phish")!,
                resourceRoot: root
            ),
            .cancel
        )
    }

    func testRequiresVersionOneNonemptyCorrelationIDAndExactNestedFields() throws {
        let invalidVersion = Data(#"{"version":2,"id":"ready-1","type":"ready"}"#.utf8)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(invalidVersion, context: localMainFrame))

        let emptyID = Data(#"{"version":1,"id":"","type":"ready"}"#.utf8)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(emptyID, context: localMainFrame))

        let unknownSnapshotField = Data(#"{"version":1,"id":"request-4","type":"changed","snapshot":{"draftID":"draft-1","title":"Note","document":{"type":"doc"},"authorization":"secret"},"expectedRevision":0}"#.utf8)
        XCTAssertThrowsError(try CaptureBridgeProtocol.decode(unknownSnapshotField, context: localMainFrame)) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .unknownField("snapshot.authorization"))
        }
    }

    func testEncodesTypedRepliesWithoutCredentialsOrGenericResultPayloads() throws {
        let reply = CaptureBridgeReply.success(
            id: "request-1",
            result: .saved(revision: 5)
        )
        let encoded = try CaptureBridgeProtocol.encode(reply)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["id"] as? String, "request-1")
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertNil(object["token"])
        XCTAssertNil(object["method"])
    }

    func testRejectsReplyWhoseTypedEnvelopeExceedsMessageCap() throws {
        let text = String(
            repeating: "x",
            count: CaptureBridgeProtocol.maximumMessageBytes - 100
        )
        let document = try JSONSerialization.data(withJSONObject: [
            "type": "doc",
            "content": [[
                "type": "paragraph",
                "content": [["type": "text", "text": text]],
            ]],
        ])
        let reply = CaptureBridgeReply.success(
            id: "large-reply",
            result: .ready(
                CaptureEditorSnapshot(
                    draftID: "draft-1",
                    title: "Large",
                    document: document,
                    revision: 1
                )
            )
        )

        XCTAssertThrowsError(try CaptureBridgeProtocol.replyObject(reply)) { error in
            XCTAssertEqual(error as? CaptureBridgeProtocolError, .messageTooLarge)
        }
    }
}
