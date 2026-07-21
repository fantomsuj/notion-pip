import Foundation

enum CaptureExport {
    static func json(
        records: [CaptureRecordSnapshot],
        drafts: [CaptureDraftSnapshot]
    ) throws -> Data {
        let object: [String: Any] = [
            "drafts": try drafts.sorted { $0.id < $1.id }.map(exportDraft),
            "records": try records.sorted { $0.id < $1.id }.map(exportRecord),
            "schemaVersion": 1,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func markdown(
        records: [CaptureRecordSnapshot],
        drafts: [CaptureDraftSnapshot]
    ) throws -> String {
        var sections = ["# Notion PiP Capture Export"]
        let sortedRecords = records.sorted { $0.id < $1.id }
        if !sortedRecords.isEmpty {
            sections.append("## Records")
            for record in sortedRecords {
                sections.append(try markdown(record: record))
            }
        }
        let sortedDrafts = drafts.sorted { $0.id < $1.id }
        if !sortedDrafts.isEmpty {
            sections.append("## Drafts")
            for draft in sortedDrafts {
                sections.append(try markdown(draft: draft))
            }
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func exportRecord(_ record: CaptureRecordSnapshot) throws -> [String: Any] {
        var result: [String: Any] = [
            "attemptCount": record.attemptCount,
            "destination": ["id": record.destination.identifier, "kind": record.destination.rawKind],
            "draftID": record.draftID,
            "editorDocument": try sanitizedDocument(record.editorDocument),
            "firstQueuedAt": dateString(record.firstQueuedAt),
            "id": record.id,
            "requiresManagedCheck": record.requiresManagedCheck,
            "revision": record.revision,
            "state": record.state.rawValue,
            "title": record.title,
            "updatedAt": dateString(record.updatedAt),
        ]
        setOptional(try record.sourceDocument.map(sanitizedDocument), key: "sourceDocument", in: &result)
        setOptional(record.nextAttemptAt.map(dateString), key: "nextAttemptAt", in: &result)
        setOptional(record.inFlightAt.map(dateString), key: "inFlightAt", in: &result)
        setOptional(record.deliveredAt.map(dateString), key: "deliveredAt", in: &result)
        setOptional(record.fingerprint, key: "fingerprint", in: &result)
        setOptional(try record.operationJournal.map(sanitizedDocument), key: "operationJournal", in: &result)
        setOptional(record.remoteIdentity, key: "remoteIdentity", in: &result)
        if let error = record.safeError {
            var safeError: [String: Any] = ["code": error.code]
            setOptional(error.message, key: "message", in: &safeError)
            setOptional(error.statusCode, key: "statusCode", in: &safeError)
            setOptional(error.retryAfter, key: "retryAfter", in: &safeError)
            result["safeError"] = safeError
        }
        return result
    }

    private static func exportDraft(_ draft: CaptureDraftSnapshot) throws -> [String: Any] {
        var result: [String: Any] = [
            "createdAt": dateString(draft.createdAt),
            "disposition": draft.disposition.rawValue,
            "editorDocument": try sanitizedDocument(draft.editorDocument),
            "id": draft.id,
            "revision": draft.revision,
            "title": draft.title,
            "updatedAt": dateString(draft.updatedAt),
        ]
        setOptional(try draft.sourceDocument.map(sanitizedDocument), key: "sourceDocument", in: &result)
        setOptional(draft.captureRecordID, key: "captureRecordID", in: &result)
        return result
    }

    private static func markdown(record: CaptureRecordSnapshot) throws -> String {
        let document = try sanitizedDocument(record.editorDocument)
        var renderer = MarkdownDocumentRenderer()
        let body = renderer.render(document)
        var parts = [
            "### \(record.title)",
            "- Capture ID: \(record.id)\n- State: \(record.state.rawValue)\n- Destination: \(record.destination.rawKind) `\(record.destination.identifier)`",
        ]
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let sourceDocument = record.sourceDocument {
            parts.append(try recoverySection(title: "Source JSON", object: sanitizedDocument(sourceDocument)))
        }
        if let operationJournal = record.operationJournal {
            parts.append(try recoverySection(title: "Operation Journal", object: sanitizedDocument(operationJournal)))
        }
        if !renderer.unknownNodes.isEmpty {
            let recovery = try renderer.unknownNodes.map(canonicalJSONString).joined(separator: "\n")
            parts.append("#### Recovery JSON\n\n```json\n\(recovery)\n```")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func markdown(draft: CaptureDraftSnapshot) throws -> String {
        let document = try sanitizedDocument(draft.editorDocument)
        var renderer = MarkdownDocumentRenderer()
        let body = renderer.render(document)
        var parts = [
            "### \(draft.title)",
            "- Draft ID: \(draft.id)\n- Disposition: \(draft.disposition.rawValue)\n- Revision: \(draft.revision)",
        ]
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let sourceDocument = draft.sourceDocument {
            parts.append(try recoverySection(title: "Source JSON", object: sanitizedDocument(sourceDocument)))
        }
        if !renderer.unknownNodes.isEmpty {
            let recovery = try renderer.unknownNodes.map(canonicalJSONString).joined(separator: "\n")
            parts.append("#### Recovery JSON\n\n```json\n\(recovery)\n```")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func recoverySection(title: String, object: Any) throws -> String {
        "#### \(title)\n\n```json\n\(try canonicalJSONString(object))\n```"
    }

    private static func sanitizedDocument(_ data: Data) throws -> Any {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return sanitize(object)
    }

    private static func sanitize(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                guard !isCredentialShaped(entry.key) else { return }
                result[entry.key] = sanitize(entry.value)
            }
        }
        if let array = object as? [Any] {
            return array.map(sanitize)
        }
        return object
    }

    private static func isCredentialShaped(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("authorization")
            || normalized.contains("password")
            || normalized.contains("apikey")
    }

    private static func canonicalJSONString(_ object: Any) throws -> String {
        String(decoding: try CanonicalJSON.encode(object), as: UTF8.self)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func setOptional<T>(_ value: T?, key: String, in dictionary: inout [String: Any]) {
        if let value { dictionary[key] = value }
    }
}

private struct MarkdownDocumentRenderer {
    var unknownNodes: [Any] = []

    mutating func render(_ object: Any) -> String {
        guard let node = object as? [String: Any], let type = node["type"] as? String else {
            unknownNodes.append(object)
            return ""
        }
        switch type {
        case "doc":
            return children(of: node).map { render($0) }.joined()
        case "paragraph":
            return renderInlineChildren(of: node) + "\n\n"
        case "text":
            return renderText(node)
        case "heading":
            let attrs = node["attrs"] as? [String: Any]
            let level = min(max(attrs?["level"] as? Int ?? 1, 1), 6)
            return String(repeating: "#", count: level) + " " + renderInlineChildren(of: node) + "\n\n"
        case "blockquote":
            let rendered = children(of: node).map { render($0) }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> " + $0 }
                .joined(separator: "\n")
            return rendered + "\n\n"
        case "bulletList":
            return renderList(node, ordered: false)
        case "orderedList":
            return renderList(node, ordered: true)
        case "listItem":
            return children(of: node).map { render($0) }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case "codeBlock":
            return "```\n\(renderInlineChildren(of: node))\n```\n\n"
        case "hardBreak":
            return "  \n"
        case "horizontalRule":
            return "---\n\n"
        default:
            unknownNodes.append(node)
            return ""
        }
    }

    private mutating func renderInlineChildren(of node: [String: Any]) -> String {
        children(of: node).map { render($0) }.joined()
    }

    private mutating func renderList(_ node: [String: Any], ordered: Bool) -> String {
        let rows = children(of: node).enumerated().map { index, child -> String in
            let content = render(child)
            let marker = ordered ? "\(index + 1)." : "-"
            return "\(marker) \(content)"
        }
        return rows.joined(separator: "\n") + "\n\n"
    }

    private func renderText(_ node: [String: Any]) -> String {
        var text = node["text"] as? String ?? ""
        let marks = node["marks"] as? [[String: Any]] ?? []
        for mark in marks.reversed() {
            switch mark["type"] as? String {
            case "bold": text = "**\(text)**"
            case "italic": text = "*\(text)*"
            case "strike": text = "~~\(text)~~"
            case "code": text = "`\(text)`"
            case "link":
                if let href = (mark["attrs"] as? [String: Any])?["href"] as? String {
                    text = "[\(text)](\(href))"
                }
            default: break
            }
        }
        return text
    }

    private func children(of node: [String: Any]) -> [Any] {
        node["content"] as? [Any] ?? []
    }
}
