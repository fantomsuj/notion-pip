import Foundation
import XCTest
@testable import NotionPiP

final class NotionBlockConverterTests: XCTestCase {
    func testJSONSerializationConversionMatchesCodableForEveryJSONValueKind() throws {
        let data = Data(
            #"{"object":{"array":[null,true,false,0,-1,1.5,"text"],"nested":{"value":42}}}"#.utf8
        )
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        let converted = try JSONValue(
            jsonObject: JSONSerialization.jsonObject(with: data)
        )

        XCTAssertEqual(converted, decoded)
    }

    func testConvertsEverySupportedEditorBlockAndInlineMark() throws {
        let document = jsonData([
            "type": "doc",
            "content": [
                ["type": "paragraph", "content": [[
                    "type": "text",
                    "text": "Styled",
                    "marks": [
                        ["type": "bold"],
                        ["type": "italic"],
                        ["type": "underline"],
                        ["type": "strike"],
                        ["type": "code"],
                        ["type": "link", "attrs": ["href": "https://example.com"]],
                    ],
                ]]],
                ["type": "heading", "attrs": ["level": 2], "content": [["type": "text", "text": "Heading"]]],
                ["type": "bulletList", "content": [[
                    "type": "listItem",
                    "content": [["type": "paragraph", "content": [["type": "text", "text": "Bullet"]]]],
                ]]],
                ["type": "orderedList", "content": [[
                    "type": "listItem",
                    "content": [["type": "paragraph", "content": [["type": "text", "text": "Number"]]]],
                ]]],
                ["type": "taskList", "content": [[
                    "type": "taskItem",
                    "attrs": ["checked": true],
                    "content": [["type": "paragraph", "content": [["type": "text", "text": "Done"]]]],
                ]]],
                ["type": "blockquote", "content": [["type": "paragraph", "content": [["type": "text", "text": "Quote"]]]]],
                ["type": "codeBlock", "attrs": ["language": "swift"], "content": [["type": "text", "text": "let x = 1"]]],
                ["type": "horizontalRule"],
            ],
        ])

        let conversion = try NotionBlockConverter().convert(document)
        let objects = try conversion.blocks.map(jsonObject)

        XCTAssertEqual(
            objects.compactMap { $0["type"] as? String },
            [
                "paragraph", "heading_2", "bulleted_list_item",
                "numbered_list_item", "to_do", "quote", "code", "divider",
            ]
        )
        let paragraph = try nestedObject(objects[0], key: "paragraph")
        let richText = try XCTUnwrap(paragraph["rich_text"] as? [[String: Any]])
        let annotations = try XCTUnwrap(richText.first?["annotations"] as? [String: Any])
        XCTAssertEqual(annotations["bold"] as? Bool, true)
        XCTAssertEqual(annotations["italic"] as? Bool, true)
        XCTAssertEqual(annotations["underline"] as? Bool, true)
        XCTAssertEqual(annotations["strikethrough"] as? Bool, true)
        XCTAssertEqual(annotations["code"] as? Bool, true)
        XCTAssertEqual(
            ((richText.first?["text"] as? [String: Any])?["link"] as? [String: Any])?["url"] as? String,
            "https://example.com"
        )
        XCTAssertTrue(conversion.unsupportedNodes.isEmpty)
    }

    func testSplitsRichTextAtTwoThousandCharactersAndBatchesAtOneHundredBlocks() throws {
        let longText = String(repeating: "x", count: 4_001)
        let document = jsonData([
            "type": "doc",
            "content": (0 ..< 201).map { index in
                [
                    "type": "paragraph",
                    "content": [["type": "text", "text": index == 0 ? longText : "\(index)"]],
                ]
            },
        ])

        let conversion = try NotionBlockConverter().convert(document)
        let first = try nestedObject(jsonObject(conversion.blocks[0]), key: "paragraph")
        let richText = try XCTUnwrap(first["rich_text"] as? [[String: Any]])

        XCTAssertEqual(richText.count, 3)
        XCTAssertEqual(richText.map(textContent), [2_000, 2_000, 1])
        XCTAssertEqual(conversion.batches.map(\.count), [100, 100, 1])
    }

    func testUnsupportedNodeCreatesVisibleRecoveryMarkerAndPreservesLocalJSON() throws {
        let document = jsonData([
            "type": "doc",
            "content": [["type": "table", "attrs": ["safe": "preserve-me"]]],
        ])

        let conversion = try NotionBlockConverter().convert(document)

        XCTAssertEqual(conversion.blocks.count, 1)
        XCTAssertEqual(conversion.unsupportedNodes.count, 1)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(conversion.blocks[0]), as: UTF8.self)
            .contains("Unsupported content preserved"))
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(conversion.unsupportedNodes[0]), as: UTF8.self)
            .contains("preserve-me"))
    }

    private func jsonObject(_ value: JSONValue) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        )
    }

    private func nestedObject(_ object: [String: Any], key: String) throws -> [String: Any] {
        try XCTUnwrap(object[key] as? [String: Any])
    }

    private func textContent(_ richText: [String: Any]) -> Int {
        (((richText["text"] as? [String: Any])?["content"] as? String) ?? "").count
    }
}
