import Foundation

/// The draft operations needed to finish a Quick Capture session.
///
/// Keeping this capability separate from the SwiftData repository lets the
/// lifecycle policy be composed with other persistence implementations.
protocol CaptureDraftFinalizing: Sendable {
    func draft(id: String) async throws -> CaptureDraftSnapshot?
    func saveDraft(
        _ mutation: DraftMutation,
        expectedRevision: Int
    ) async throws -> CaptureDraftSnapshot
    func discardDraft(id: String, expectedRevision: Int) async throws
    func enqueue(
        draftID: String,
        expectedRevision: Int,
        destination: CaptureDestination
    ) async throws -> CaptureRecordSnapshot
}

/// Persistence operations used by the delivery state machine.
protocol CaptureDeliveryPersisting: Sendable {
    func claimNext(
        at now: Date,
        retryPolicy: RetryPolicy
    ) async throws -> CaptureRecordSnapshot?
    func markDelivered(
        recordID: String,
        receipt: DeliveryReceipt,
        at now: Date
    ) async throws -> CaptureRecordSnapshot
    func markRetrying(
        recordID: String,
        nextAttemptAt: Date?,
        requiresManagedCheck: Bool,
        safeError: SafeDeliveryError,
        at now: Date
    ) async throws -> CaptureRecordSnapshot
    func markBlockedConflict(
        recordID: String,
        safeError: SafeDeliveryError,
        at now: Date
    ) async throws -> CaptureRecordSnapshot
    func markUncertain(
        recordID: String,
        safeError: SafeDeliveryError,
        at now: Date
    ) async throws -> CaptureRecordSnapshot
    func recoverInterruptedWork(at now: Date) async throws -> Int
}

/// Queue metadata used to schedule delivery and retention work.
protocol CaptureDeliveryScheduling: Sendable {
    func records() async throws -> [CaptureRecordSnapshot]
    func resumeUnauthorizedRetries(at now: Date) async throws -> Int
    func applyRetention(
        at now: Date,
        policy: RetentionPolicy
    ) async throws -> RetentionResult
}

/// Journal persistence needed while a remote page is delivered in batches.
protocol CaptureDeliveryJournaling: Sendable {
    func updateDeliveryJournal(
        recordID: String,
        journal: Data?
    ) async throws -> CaptureRecordSnapshot
}

extension CaptureRepository: CaptureDraftFinalizing {}
extension CaptureRepository: CaptureDeliveryPersisting {}
extension CaptureRepository: CaptureDeliveryScheduling {}
extension CaptureRepository: CaptureDeliveryJournaling {}
