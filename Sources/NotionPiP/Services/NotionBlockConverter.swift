import Foundation

struct NotionBlockConversion: Equatable, Sendable {
    let blocks: [JSONValue]
    let unsupportedNodes: [JSONValue]

    var batches: [[JSONValue]] {
        stride(from: 0, to: blocks.count, by: 100).map { start in
            Array(blocks[start ..< min(start + 100, blocks.count)])
        }
    }
}

enum NotionBlockConversionError: Error, Equatable {
    case malformedDocument
}

struct NotionBlockConverter {
    func convert(_ document: Data) throws -> NotionBlockConversion {
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: document)
        } catch {
            throw NotionBlockConversionError.malformedDocument
        }
        guard case let .object(rootObject) = root,
              rootObject.string("type") == "doc"
        else {
            throw NotionBlockConversionError.malformedDocument
        }

        var context = ConversionContext()
        let blocks = rootObject.array("content").flatMap { context.convertBlock($0) }
        return NotionBlockConversion(
            blocks: blocks,
            unsupportedNodes: context.unsupportedNodes
        )
    }
}

private struct ConversionContext {
    var unsupportedNodes: [JSONValue] = []

    mutating func convertBlock(_ value: JSONValue) -> [JSONValue] {
        guard case let .object(node) = value, let type = node.string("type") else {
            return unsupported(value)
        }
        switch type {
        case "paragraph":
            return [block(type: "paragraph", payload: richTextPayload(node))]
        case "heading":
            let level = min(max(node.object("attrs")?.integer("level") ?? 1, 1), 3)
            let type = "heading_\(level)"
            return [block(type: type, payload: richTextPayload(node))]
        case "bulletList":
            return convertList(node, blockType: "bulleted_list_item")
        case "orderedList":
            return convertList(node, blockType: "numbered_list_item")
        case "taskList":
            return node.array("content").flatMap { convertTaskItem($0) }
        case "blockquote":
            return [block(type: "quote", payload: richTextPayload(node, recursively: true))]
        case "codeBlock":
            let language = node.object("attrs")?.string("language") ?? "plain text"
            return [
                block(
                    type: "code",
                    payload: [
                        "rich_text": .array(richText(in: node, recursively: true)),
                        "language": .string(language),
                    ]
                ),
            ]
        case "horizontalRule":
            return [block(type: "divider", payload: [:])]
        default:
            return unsupported(value)
        }
    }

    private mutating func convertList(
        _ node: [String: JSONValue],
        blockType: String
    ) -> [JSONValue] {
        node.array("content").flatMap { item in
            guard case let .object(itemObject) = item,
                  itemObject.string("type") == "listItem"
            else {
                return unsupported(item)
            }
            let children = itemObject.array("content")
            let firstTextNode = children.first ?? .object([:])
            var payload = richTextPayload(
                firstTextNode.objectValue ?? [:],
                recursively: true
            )
            let nestedBlocks = children.dropFirst().flatMap { convertBlock($0) }
            if !nestedBlocks.isEmpty {
                payload["children"] = .array(nestedBlocks)
            }
            return [block(type: blockType, payload: payload)]
        }
    }

    private mutating func convertTaskItem(_ item: JSONValue) -> [JSONValue] {
        guard case let .object(itemObject) = item,
              itemObject.string("type") == "taskItem"
        else {
            return unsupported(item)
        }
        var payload = richTextPayload(itemObject, recursively: true)
        payload["checked"] = .bool(
            itemObject.object("attrs")?.bool("checked") ?? false
        )
        return [block(type: "to_do", payload: payload)]
    }

    private mutating func richTextPayload(
        _ node: [String: JSONValue],
        recursively: Bool = false
    ) -> [String: JSONValue] {
        [
            "rich_text": .array(richText(in: node, recursively: recursively)),
        ]
    }

    private mutating func richText(
        in node: [String: JSONValue],
        recursively: Bool
    ) -> [JSONValue] {
        var result: [JSONValue] = []
        for child in node.array("content") {
            guard case let .object(childObject) = child,
                  let type = childObject.string("type")
            else {
                unsupportedNodes.append(child)
                continue
            }
            switch type {
            case "text":
                result.append(contentsOf: richTextItems(for: childObject))
            case "hardBreak":
                result.append(contentsOf: richTextItems(text: "\n", marks: []))
            default:
                if recursively {
                    result.append(contentsOf: richText(in: childObject, recursively: true))
                } else {
                    unsupportedNodes.append(child)
                }
            }
        }
        return result
    }

    private func richTextItems(for node: [String: JSONValue]) -> [JSONValue] {
        richTextItems(
            text: node.string("text") ?? "",
            marks: node.array("marks")
        )
    }

    private func richTextItems(
        text: String,
        marks: [JSONValue]
    ) -> [JSONValue] {
        let markObjects = marks.compactMap(\.objectValue)
        let annotations: [String: JSONValue] = [
            "bold": .bool(markObjects.contains { $0.string("type") == "bold" }),
            "italic": .bool(markObjects.contains { $0.string("type") == "italic" }),
            "strikethrough": .bool(markObjects.contains { $0.string("type") == "strike" }),
            "underline": .bool(markObjects.contains { $0.string("type") == "underline" }),
            "code": .bool(markObjects.contains { $0.string("type") == "code" }),
            "color": .string("default"),
        ]
        let linkURL = markObjects
            .first { $0.string("type") == "link" }?
            .object("attrs")?
            .string("href")
            .flatMap(safeWebURL)

        return text.chunks(maximumCount: 2_000).map { chunk in
            var textPayload: [String: JSONValue] = ["content": .string(chunk)]
            if let linkURL {
                textPayload["link"] = .object(["url": .string(linkURL)])
            } else {
                textPayload["link"] = .null
            }
            return .object([
                "type": .string("text"),
                "text": .object(textPayload),
                "annotations": .object(annotations),
                "plain_text": .string(chunk),
                "href": linkURL.map(JSONValue.string) ?? .null,
            ])
        }
    }

    private func safeWebURL(_ rawValue: String) -> String? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else {
            return nil
        }
        return rawValue
    }

    private func block(
        type: String,
        payload: [String: JSONValue]
    ) -> JSONValue {
        .object([
            "object": .string("block"),
            "type": .string(type),
            type: .object(payload),
        ])
    }

    private mutating func unsupported(_ value: JSONValue) -> [JSONValue] {
        unsupportedNodes.append(value)
        return [
            block(
                type: "paragraph",
                payload: [
                    "rich_text": .array(
                        richTextItems(
                            text: "[Unsupported content preserved in Notion PiP]",
                            marks: []
                        )
                    ),
                ]
            ),
        ]
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }

    func array(_ key: String) -> [JSONValue] {
        guard case let .array(value)? = self[key] else { return [] }
        return value
    }

    func object(_ key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    func integer(_ key: String) -> Int? {
        guard case let .number(value)? = self[key] else { return nil }
        return Int(value)
    }

    func bool(_ key: String) -> Bool? {
        guard case let .bool(value)? = self[key] else { return nil }
        return value
    }
}

private extension String {
    func chunks(maximumCount: Int) -> [String] {
        guard !isEmpty else { return [] }
        var result: [String] = []
        var startIndex = startIndex
        while startIndex < endIndex {
            let endIndex = index(
                startIndex,
                offsetBy: maximumCount,
                limitedBy: endIndex
            ) ?? endIndex
            result.append(String(self[startIndex ..< endIndex]))
            startIndex = endIndex
        }
        return result
    }
}
