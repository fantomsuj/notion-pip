import Foundation
import XCTest
@testable import NotionPiP

final class CaptureExportTests: XCTestCase {
    func testJSONExportIsDeterministicSortedAndRecursivelyRedacted() throws {
        let recordA = record(
            id: "a-record",
            editor: [
                "type": "doc",
                "content": [
                    [
                        "type": "mystery",
                        "attrs": [
                            "keep": "visible",
                            "apiKey": "credential-value",
                            "nested": [[
                                "Refresh-Token": "refresh-value",
                                "private_key": "private-key-value",
                                "signingKey": "signing-key-value",
                                "clientKey": "client-key-value",
                                "authorizationHeader": "authorization-value",
                                "tokenValue": "token-value",
                                "secretValue": "secret-value",
                                "monkey": "banana",
                                "keyboardShortcut": "command-p",
                                "tokenCount": 3,
                                "secretary": "Alex",
                                "safe": true,
                            ]],
                        ],
                    ],
                ],
                "Authorization": "Bearer top-secret",
            ],
            source: ["Password": "password-value", "url": "https://example.com"]
        )
        let recordB = record(id: "b-record", editor: ["type": "doc", "content": []])
        let draft = CaptureDraftSnapshot(
            id: "draft-z",
            revision: 4,
            title: "Draft",
            editorDocument: jsonData(["type": "doc", "content": []]),
            sourceDocument: jsonData(["token": "draft-token", "safe": "draft-safe"]),
            disposition: .stashed,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            captureRecordID: nil,
            returnDraftID: nil
        )

        let first = try CaptureExport.json(records: [recordB, recordA], drafts: [draft])
        let second = try CaptureExport.json(records: [recordA, recordB], drafts: [draft])
        let text = String(decoding: first, as: UTF8.self)

        XCTAssertEqual(first, second)
        XCTAssertFalse(text.contains("credential-value"))
        XCTAssertFalse(text.contains("refresh-value"))
        XCTAssertFalse(text.contains("password-value"))
        XCTAssertFalse(text.contains("draft-token"))
        XCTAssertFalse(text.contains("private-key-value"))
        XCTAssertFalse(text.contains("signing-key-value"))
        XCTAssertFalse(text.contains("client-key-value"))
        XCTAssertFalse(text.contains("authorization-value"))
        XCTAssertFalse(text.contains("token-value"))
        XCTAssertFalse(text.contains("secret-value"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("authorization"))
        XCTAssertTrue(text.contains(#""monkey":"banana""#))
        XCTAssertTrue(text.contains(#""keyboardShortcut":"command-p""#))
        XCTAssertTrue(text.contains(#""tokenCount":3"#))
        XCTAssertTrue(text.contains(#""secretary":"Alex""#))
        XCTAssertTrue(text.contains(#""type":"mystery""#))
        XCTAssertTrue(text.contains(#""keep":"visible""#))
        XCTAssertTrue(text.contains(#""safe":"draft-safe""#))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let records = try XCTUnwrap(object["records"] as? [[String: Any]])
        XCTAssertEqual(records.compactMap { $0["id"] as? String }, ["a-record", "b-record"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    }

    func testMarkdownConvertsSupportedNodesAndAppendsRedactedUnknownRecoveryJSON() throws {
        let document: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "heading", "attrs": ["level": 2], "content": [["type": "text", "text": "Heading"]]],
                [
                    "type": "paragraph",
                    "content": [
                        ["type": "text", "text": "Bold", "marks": [["type": "bold"]]],
                        ["type": "text", "text": " and plain"],
                    ],
                ],
                [
                    "type": "mystery",
                    "attrs": [
                        "access_token": "remove-me",
                        "private_key": "remove-private-key",
                        "signingKey": "remove-signing-key",
                        "clientKey": "remove-client-key",
                        "authorizationHeader": "remove-authorization",
                        "tokenValue": "remove-token-value",
                        "secretValue": "remove-secret-value",
                        "monkey": "keep-banana",
                        "tokenCount": 4,
                        "secretary": "keep-name",
                        "safe": "recover-me",
                    ],
                ],
            ],
        ]
        let record = record(id: "capture-1", editor: document)

        let markdown = try CaptureExport.markdown(records: [record], drafts: [])

        XCTAssertTrue(markdown.contains("## Heading"))
        XCTAssertTrue(markdown.contains("**Bold** and plain"))
        XCTAssertTrue(markdown.contains("Recovery JSON"))
        XCTAssertTrue(markdown.contains(#""safe":"recover-me""#))
        XCTAssertTrue(markdown.contains(#""type":"mystery""#))
        XCTAssertFalse(markdown.contains("remove-me"))
        XCTAssertFalse(markdown.contains("remove-private-key"))
        XCTAssertFalse(markdown.contains("remove-signing-key"))
        XCTAssertFalse(markdown.contains("remove-client-key"))
        XCTAssertFalse(markdown.contains("remove-authorization"))
        XCTAssertFalse(markdown.contains("remove-token-value"))
        XCTAssertFalse(markdown.contains("remove-secret-value"))
        XCTAssertFalse(markdown.localizedCaseInsensitiveContains("access_token"))
        XCTAssertTrue(markdown.contains(#""monkey":"keep-banana""#))
        XCTAssertTrue(markdown.contains(#""tokenCount":4"#))
        XCTAssertTrue(markdown.contains(#""secretary":"keep-name""#))
    }

    func testMarkdownExportIsDeterministicAndIncludesUnresolvedStateAndSourceRecovery() throws {
        let uncertain = record(
            id: "a-uncertain",
            editor: ["type": "doc", "content": []],
            source: ["source": "browser", "secret": "remove-source-secret"]
        )
        let delivered = record(id: "z-delivered", editor: ["type": "doc", "content": []], state: .delivered)

        let first = try CaptureExport.markdown(records: [delivered, uncertain], drafts: [])
        let second = try CaptureExport.markdown(records: [uncertain, delivered], drafts: [])

        XCTAssertEqual(first, second)
        XCTAssertLessThan(
            try XCTUnwrap(first.range(of: "a-uncertain")?.lowerBound),
            try XCTUnwrap(first.range(of: "z-delivered")?.lowerBound)
        )
        XCTAssertTrue(first.contains("State: uncertain"))
        XCTAssertTrue(first.contains("Source JSON"))
        XCTAssertTrue(first.contains(#"{"source":"browser"}"#))
        XCTAssertFalse(first.contains("remove-source-secret"))
    }

    func testMarkdownRendersUntitledTaskListsAndIndentsNestedContent() throws {
        let document: [String: Any] = [
            "type": "doc",
            "content": [[
                "type": "taskList",
                "content": [
                    [
                        "type": "taskItem",
                        "attrs": ["checked": false],
                        "content": [
                            [
                                "type": "paragraph",
                                "content": [["type": "text", "text": "Ship lifecycle"]],
                            ],
                            [
                                "type": "taskList",
                                "content": [[
                                    "type": "taskItem",
                                    "attrs": ["checked": true],
                                    "content": [[
                                        "type": "paragraph",
                                        "content": [["type": "text", "text": "Verify nested task"]],
                                    ]],
                                ]],
                            ],
                            ["type": "futureTaskMetadata", "attrs": ["safe": "recover-me"]],
                        ],
                    ],
                    [
                        "type": "taskItem",
                        "attrs": ["checked": true],
                        "content": [[
                            "type": "paragraph",
                            "content": [["type": "text", "text": "Keep protocol stable"]],
                        ]],
                    ],
                ],
            ]],
        ]
        let untitled = record(id: "task-record", title: "", editor: document)

        let markdown = try CaptureExport.markdown(records: [untitled], drafts: [])

        XCTAssertTrue(markdown.contains("### Untitled"), markdown)
        XCTAssertTrue(
            markdown.contains(
                "- [ ] Ship lifecycle\n  - [x] Verify nested task\n- [x] Keep protocol stable"
            ),
            markdown
        )
        XCTAssertTrue(markdown.contains("Recovery JSON"), markdown)
        XCTAssertTrue(markdown.contains(#""type":"futureTaskMetadata""#), markdown)
        XCTAssertTrue(markdown.contains(#""safe":"recover-me""#), markdown)
    }

    private func record(
        id: String,
        title: String? = nil,
        editor: [String: Any],
        source: [String: Any]? = nil,
        state: DeliveryState = .uncertain
    ) -> CaptureRecordSnapshot {
        CaptureRecordSnapshot(
            id: id,
            draftID: id,
            enqueuedDraftRevision: 2,
            revision: 3,
            title: title ?? "Record \(id)",
            editorDocument: jsonData(editor),
            sourceDocument: source.map(jsonData),
            destination: .managed(databaseID: "database-1"),
            state: state,
            attemptCount: 2,
            firstQueuedAt: fixedDate,
            nextAttemptAt: nil,
            inFlightAt: nil,
            deliveredAt: state == .delivered ? fixedDate : nil,
            updatedAt: fixedDate,
            fingerprint: "fingerprint",
            operationJournal: jsonData(["stage": "recovery", "clientSecret": "journal-secret"]),
            remoteIdentity: "page-1",
            safeError: SafeDeliveryError(
                code: "needsReview",
                message: "Review this capture",
                statusCode: 500,
                retryAfter: nil
            ),
            requiresManagedCheck: state != .delivered
        )
    }

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_234)
    }
}
