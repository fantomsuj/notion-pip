import Foundation

enum CanonicalCaptureDocumentError: Error {
    case invalidDocument
}

/// A validated ProseMirror document whose JSON keys are already canonicalized.
struct CanonicalCaptureDocument: Equatable, Sendable {
    let data: Data

    /// Wraps bytes already validated and sorted by this process.
    init(trustingCanonicalData data: Data) {
        self.data = data
    }

    init(validating data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        try self.init(validatingParsedJSONObject: object)
    }

    init(validatingJSONObject object: Any) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CanonicalCaptureDocumentError.invalidDocument
        }
        try self.init(validatingParsedJSONObject: object)
    }

    /// Validates the document shape without re-walking values already produced by JSONSerialization.
    init(validatingParsedJSONObject object: Any) throws {
        guard let document = object as? [String: Any],
              document["type"] as? String == "doc",
              document["content"] is [Any]
        else {
            throw CanonicalCaptureDocumentError.invalidDocument
        }
        do {
            data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        } catch {
            throw CanonicalCaptureDocumentError.invalidDocument
        }
    }
}

struct DraftMutation: Equatable, Sendable {
    let id: String
    let title: String
    let editorDocument: Data
    let canonicalEditorDocument: CanonicalCaptureDocument?
    let sourceDocument: Data?
    let disposition: DraftDisposition

    init(
        id: String,
        title: String,
        editorDocument: Data,
        sourceDocument: Data?,
        disposition: DraftDisposition
    ) {
        self.id = id
        self.title = title
        self.editorDocument = editorDocument
        canonicalEditorDocument = nil
        self.sourceDocument = sourceDocument
        self.disposition = disposition
    }

    init(
        id: String,
        title: String,
        canonicalEditorDocument: CanonicalCaptureDocument,
        sourceDocument: Data?,
        disposition: DraftDisposition
    ) {
        self.id = id
        self.title = title
        editorDocument = canonicalEditorDocument.data
        self.canonicalEditorDocument = canonicalEditorDocument
        self.sourceDocument = sourceDocument
        self.disposition = disposition
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.editorDocument == rhs.editorDocument
            && lhs.sourceDocument == rhs.sourceDocument
            && lhs.disposition == rhs.disposition
    }
}

struct CaptureDraftSnapshot: Codable, Equatable, Sendable {
    let id: String
    let revision: Int
    let title: String
    let editorDocument: Data
    let sourceDocument: Data?
    let disposition: DraftDisposition
    let createdAt: Date
    let updatedAt: Date
    let captureRecordID: String?
    let returnDraftID: String?
}

struct CaptureRecordSnapshot: Codable, Equatable, Sendable {
    let id: String
    let draftID: String
    let enqueuedDraftRevision: Int
    let revision: Int
    let title: String
    let editorDocument: Data
    let sourceDocument: Data?
    let destination: CaptureDestination
    let state: DeliveryState
    let attemptCount: Int
    let firstQueuedAt: Date
    let nextAttemptAt: Date?
    let inFlightAt: Date?
    let deliveredAt: Date?
    let updatedAt: Date
    let fingerprint: String?
    let operationJournal: Data?
    let remoteIdentity: String?
    let safeError: SafeDeliveryError?
    let requiresManagedCheck: Bool
}

/// Blob-free delivery metadata used by the capture outbox.
struct CaptureRecordSummary: Equatable, Sendable {
    let id: String
    let title: String
    let state: DeliveryState
    let updatedAt: Date
    let safeError: SafeDeliveryError?
}

enum CanonicalJSON {
    static func canonicalize(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    static func encode(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}
