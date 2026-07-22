import Foundation
import SwiftData

@Model
final class CaptureRecordModel {
    @Attribute(.unique) var stableID: String
    var draftID: String
    var enqueuedDraftRevision: Int
    var revision: Int
    var title: String
    var editorDocument: Data
    var sourceDocument: Data?
    var destinationKind: String
    var destinationID: String
    var stateRawValue: String
    var attemptCount: Int
    var firstQueuedAt: Date
    var nextAttemptAt: Date?
    var inFlightAt: Date?
    var deliveredAt: Date?
    var updatedAt: Date
    var fingerprint: String?
    var operationJournal: Data?
    var remoteIdentity: String?
    var safeErrorCode: String?
    var safeErrorMessage: String?
    var safeErrorStatusCode: Int?
    var safeErrorRetryAfter: TimeInterval?
    var requiresManagedCheck: Bool

    init(
        stableID: String,
        draftID: String,
        enqueuedDraftRevision: Int,
        revision: Int,
        title: String,
        editorDocument: Data,
        sourceDocument: Data?,
        destinationKind: String,
        destinationID: String,
        stateRawValue: String,
        attemptCount: Int,
        firstQueuedAt: Date,
        nextAttemptAt: Date?,
        inFlightAt: Date?,
        deliveredAt: Date?,
        updatedAt: Date,
        fingerprint: String? = nil,
        operationJournal: Data? = nil,
        remoteIdentity: String? = nil,
        safeErrorCode: String? = nil,
        safeErrorMessage: String? = nil,
        safeErrorStatusCode: Int? = nil,
        safeErrorRetryAfter: TimeInterval? = nil,
        requiresManagedCheck: Bool = false
    ) {
        self.stableID = stableID
        self.draftID = draftID
        self.enqueuedDraftRevision = enqueuedDraftRevision
        self.revision = revision
        self.title = title
        self.editorDocument = editorDocument
        self.sourceDocument = sourceDocument
        self.destinationKind = destinationKind
        self.destinationID = destinationID
        self.stateRawValue = stateRawValue
        self.attemptCount = attemptCount
        self.firstQueuedAt = firstQueuedAt
        self.nextAttemptAt = nextAttemptAt
        self.inFlightAt = inFlightAt
        self.deliveredAt = deliveredAt
        self.updatedAt = updatedAt
        self.fingerprint = fingerprint
        self.operationJournal = operationJournal
        self.remoteIdentity = remoteIdentity
        self.safeErrorCode = safeErrorCode
        self.safeErrorMessage = safeErrorMessage
        self.safeErrorStatusCode = safeErrorStatusCode
        self.safeErrorRetryAfter = safeErrorRetryAfter
        self.requiresManagedCheck = requiresManagedCheck
    }
}
