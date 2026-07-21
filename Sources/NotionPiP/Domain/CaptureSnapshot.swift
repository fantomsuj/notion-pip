import Foundation

struct DraftMutation: Equatable, Sendable {
    let id: String
    let title: String
    let editorDocument: Data
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
        self.sourceDocument = sourceDocument
        self.disposition = disposition
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
}

struct CaptureRecordSnapshot: Codable, Equatable, Sendable {
    let id: String
    let draftID: String
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

enum CanonicalJSON {
    static func canonicalize(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    static func encode(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}
