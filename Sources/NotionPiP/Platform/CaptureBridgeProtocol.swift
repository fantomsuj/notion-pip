import Foundation

struct BridgeMessageContext: Equatable, Sendable {
    let isMainFrame: Bool
    let originScheme: String
    let originHost: String
    let sourceURL: URL?
    let allowedDocumentURL: URL
}

struct CaptureEditorSnapshot: Equatable, Sendable {
    let draftID: String
    let title: String
    let document: Data
    let revision: Int?
    let canonicalDocument: CanonicalCaptureDocument?

    var hasValidatedCanonicalDocument: Bool { canonicalDocument != nil }

    init(draftID: String, title: String, document: Data, revision: Int? = nil) {
        self.draftID = draftID
        self.title = title
        self.document = document
        self.revision = revision
        canonicalDocument = nil
    }

    init(
        draftID: String,
        title: String,
        canonicalDocument: CanonicalCaptureDocument,
        revision: Int? = nil
    ) {
        self.draftID = draftID
        self.title = title
        document = canonicalDocument.data
        self.revision = revision
        self.canonicalDocument = canonicalDocument
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.draftID == rhs.draftID
            && lhs.title == rhs.title
            && lhs.document == rhs.document
            && lhs.revision == rhs.revision
    }
}

enum CaptureConflictAction: String, Codable, CaseIterable, Sendable {
    case reloadLatest
    case saveAsNew
    case openInNotion
}

enum CaptureBridgeRequest: Equatable, Sendable {
    case ready(id: String)
    case changed(id: String, snapshot: CaptureEditorSnapshot, expectedRevision: Int)
    case save(id: String, snapshot: CaptureEditorSnapshot, expectedRevision: Int)
    case stash(id: String, snapshot: CaptureEditorSnapshot, expectedRevision: Int)
    case restore(id: String, draftID: String, expectedRevision: Int)
    case resolveConflict(id: String, action: CaptureConflictAction, snapshot: CaptureEditorSnapshot)

    var id: String {
        switch self {
        case let .ready(id),
             let .changed(id, _, _),
             let .save(id, _, _),
             let .stash(id, _, _),
             let .restore(id, _, _),
             let .resolveConflict(id, _, _):
            id
        }
    }
}

enum CaptureBridgeResultKind: String, Equatable, Sendable {
    case ready
    case changed
    case saved
    case stashed
    case restored
    case conflictResolved
}

struct CaptureBridgeResult: Equatable, Sendable {
    let kind: CaptureBridgeResultKind
    let revision: Int?
    let snapshot: CaptureEditorSnapshot?

    static func ready(_ snapshot: CaptureEditorSnapshot) -> Self {
        Self(kind: .ready, revision: snapshot.revision, snapshot: snapshot)
    }

    static func changed(revision: Int) -> Self {
        Self(kind: .changed, revision: revision, snapshot: nil)
    }

    static func saved(revision: Int) -> Self {
        Self(kind: .saved, revision: revision, snapshot: nil)
    }

    static func stashed(_ snapshot: CaptureEditorSnapshot) -> Self {
        Self(kind: .stashed, revision: snapshot.revision, snapshot: snapshot)
    }

    static func restored(_ snapshot: CaptureEditorSnapshot) -> Self {
        Self(kind: .restored, revision: snapshot.revision, snapshot: snapshot)
    }

    static func conflictResolved(_ snapshot: CaptureEditorSnapshot?) -> Self {
        Self(kind: .conflictResolved, revision: snapshot?.revision, snapshot: snapshot)
    }
}

enum CaptureBridgeErrorCode: String, Equatable, Sendable {
    case invalidMessage
    case staleRevision
    case draftNotFound
    case persistenceFailure
    case unsupportedAction
}

struct CaptureBridgeErrorReply: Equatable, Sendable {
    let code: CaptureBridgeErrorCode
    let message: String
    let recoverable: Bool
    let latest: CaptureEditorSnapshot?
}

struct CaptureBridgeReply: Equatable, Sendable {
    static let version = 1

    let id: String
    let result: CaptureBridgeResult?
    let error: CaptureBridgeErrorReply?

    static func success(id: String, result: CaptureBridgeResult) -> Self {
        Self(id: id, result: result, error: nil)
    }

    static func failure(
        id: String,
        code: CaptureBridgeErrorCode,
        message: String,
        recoverable: Bool,
        latest: CaptureEditorSnapshot? = nil
    ) -> Self {
        Self(
            id: id,
            result: nil,
            error: CaptureBridgeErrorReply(
                code: code,
                message: message,
                recoverable: recoverable,
                latest: latest
            )
        )
    }
}

enum CaptureBridgeProtocolError: Error, Equatable {
    case messageTooLarge
    case notMainFrame
    case untrustedOrigin
    case malformedMessage
    case unsupportedVersion
    case invalidRequestID
    case unsupportedType(String)
    case unknownField(String)
    case invalidDocument
}

enum CaptureBridgeProtocol {
    static let version = 1
    static let handlerName = "captureBridge"
    static let maximumMessageBytes = 1_048_576

    static func decode(_ data: Data, context: BridgeMessageContext) throws -> CaptureBridgeRequest {
        guard data.count <= maximumMessageBytes else {
            throw CaptureBridgeProtocolError.messageTooLarge
        }
        guard context.isMainFrame else {
            throw CaptureBridgeProtocolError.notMainFrame
        }
        guard context.originScheme == "file", context.originHost.isEmpty else {
            throw CaptureBridgeProtocolError.untrustedOrigin
        }
        guard context.sourceURL?.standardizedFileURL.resolvingSymlinksInPath()
                == context.allowedDocumentURL.standardizedFileURL.resolvingSymlinksInPath()
        else {
            throw CaptureBridgeProtocolError.untrustedOrigin
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
        guard integer(dictionary["version"]) == version else {
            throw CaptureBridgeProtocolError.unsupportedVersion
        }
        guard let id = dictionary["id"] as? String,
              !id.isEmpty,
              id.utf8.count <= 128
        else {
            throw CaptureBridgeProtocolError.invalidRequestID
        }
        guard let type = dictionary["type"] as? String else {
            throw CaptureBridgeProtocolError.malformedMessage
        }

        switch type {
        case "ready":
            try requireExactFields(dictionary, allowed: ["version", "id", "type"])
            return .ready(id: id)
        case "changed":
            try requireExactFields(
                dictionary,
                allowed: ["version", "id", "type", "snapshot", "expectedRevision"]
            )
            return .changed(
                id: id,
                snapshot: try snapshot(dictionary["snapshot"]),
                expectedRevision: try nonnegativeInteger(dictionary["expectedRevision"])
            )
        case "save":
            try requireExactFields(
                dictionary,
                allowed: ["version", "id", "type", "snapshot", "expectedRevision"]
            )
            return .save(
                id: id,
                snapshot: try snapshot(dictionary["snapshot"]),
                expectedRevision: try nonnegativeInteger(dictionary["expectedRevision"])
            )
        case "stash":
            try requireExactFields(
                dictionary,
                allowed: ["version", "id", "type", "snapshot", "expectedRevision"]
            )
            return .stash(
                id: id,
                snapshot: try snapshot(dictionary["snapshot"]),
                expectedRevision: try nonnegativeInteger(dictionary["expectedRevision"])
            )
        case "restore":
            try requireExactFields(
                dictionary,
                allowed: ["version", "id", "type", "draftID", "expectedRevision"]
            )
            return .restore(
                id: id,
                draftID: try identifier(dictionary["draftID"]),
                expectedRevision: try nonnegativeInteger(dictionary["expectedRevision"])
            )
        case "resolveConflict":
            try requireExactFields(
                dictionary,
                allowed: ["version", "id", "type", "action", "snapshot"]
            )
            guard let actionValue = dictionary["action"] as? String,
                  let action = CaptureConflictAction(rawValue: actionValue)
            else {
                throw CaptureBridgeProtocolError.malformedMessage
            }
            return .resolveConflict(
                id: id,
                action: action,
                snapshot: try snapshot(dictionary["snapshot"])
            )
        default:
            throw CaptureBridgeProtocolError.unsupportedType(type)
        }
    }

    static func encode(_ reply: CaptureBridgeReply) throws -> Data {
        try JSONSerialization.data(withJSONObject: replyObject(reply), options: [.sortedKeys])
    }

    static func replyObject(_ reply: CaptureBridgeReply) throws -> [String: Any] {
        var object: [String: Any] = [
            "version": CaptureBridgeReply.version,
            "id": reply.id,
        ]
        if let result = reply.result {
            object["ok"] = true
            var resultObject: [String: Any] = ["kind": result.kind.rawValue]
            if let revision = result.revision {
                resultObject["revision"] = revision
            }
            if let snapshot = result.snapshot {
                resultObject["snapshot"] = try snapshotObject(snapshot)
            }
            object["result"] = resultObject
        } else if let error = reply.error {
            object["ok"] = false
            var errorObject: [String: Any] = [
                "code": error.code.rawValue,
                "message": error.message,
                "recoverable": error.recoverable,
            ]
            if let latest = error.latest {
                errorObject["latest"] = try snapshotObject(latest)
            }
            object["error"] = errorObject
        } else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
        guard try JSONSerialization.data(withJSONObject: object).count <= maximumMessageBytes else {
            throw CaptureBridgeProtocolError.messageTooLarge
        }
        return object
    }

    static func canonicalDocument(_ data: Data) throws -> Data {
        guard data.count <= maximumMessageBytes else {
            throw CaptureBridgeProtocolError.invalidDocument
        }
        do {
            return try CanonicalCaptureDocument(validating: data).data
        } catch {
            throw CaptureBridgeProtocolError.invalidDocument
        }
    }

    private static func snapshot(_ value: Any?) throws -> CaptureEditorSnapshot {
        guard let dictionary = value as? [String: Any] else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
        try requireExactFields(
            dictionary,
            allowed: ["draftID", "title", "document"],
            path: "snapshot."
        )
        guard let title = dictionary["title"] as? String,
              title.utf8.count <= 32_768,
              let document = dictionary["document"]
        else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
        let canonicalDocument: CanonicalCaptureDocument
        do {
            canonicalDocument = try CanonicalCaptureDocument(
                validatingParsedJSONObject: document
            )
        } catch {
            throw CaptureBridgeProtocolError.invalidDocument
        }
        guard canonicalDocument.data.count <= maximumMessageBytes else {
            throw CaptureBridgeProtocolError.invalidDocument
        }
        return CaptureEditorSnapshot(
            draftID: try identifier(dictionary["draftID"]),
            title: title,
            canonicalDocument: canonicalDocument
        )
    }

    private static func snapshotObject(_ snapshot: CaptureEditorSnapshot) throws -> [String: Any] {
        let documentData = try snapshot.canonicalDocument?.data
            ?? canonicalDocument(snapshot.document)
        let document = try JSONSerialization.jsonObject(with: documentData)
        var object: [String: Any] = [
            "draftID": snapshot.draftID,
            "title": snapshot.title,
            "document": document,
        ]
        if let revision = snapshot.revision {
            object["revision"] = revision
        }
        return object
    }

    private static func requireExactFields(
        _ dictionary: [String: Any],
        allowed: Set<String>,
        path: String = ""
    ) throws {
        if let unknown = dictionary.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw CaptureBridgeProtocolError.unknownField(path + unknown)
        }
        guard dictionary.count == allowed.count,
              allowed.allSatisfy({ dictionary[$0] != nil })
        else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
    }

    private static func identifier(_ value: Any?) throws -> String {
        guard let identifier = value as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              identifier.utf8.count <= 256
        else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
        return identifier
    }

    private static func nonnegativeInteger(_ value: Any?) throws -> Int {
        guard let result = integer(value), result >= 0 else {
            throw CaptureBridgeProtocolError.malformedMessage
        }
        return result
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let double = number.doubleValue
        guard double.rounded() == double,
              double >= Double(Int.min),
              double <= Double(Int.max)
        else {
            return nil
        }
        return number.intValue
    }
}
