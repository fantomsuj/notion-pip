import Foundation

struct DeliveryReceipt: Equatable, Sendable {
    let remoteIdentity: String
    let fingerprint: String?
}

enum DeliveryTransportError: Error, Equatable, Sendable {
    case http(status: Int, retryAfter: TimeInterval?, message: String?)
    case ambiguous(message: String?)
    case transport(message: String?)
}

protocol CaptureDeliveryTransport: Sendable {
    func findManagedCapture(captureID: String, databaseID: String) async throws -> DeliveryReceipt?
    func createManaged(_ record: CaptureRecordSnapshot, databaseID: String) async throws -> DeliveryReceipt
    func appendManual(_ record: CaptureRecordSnapshot, pageID: String) async throws -> DeliveryReceipt
}

struct DeliveryDrainSummary: Equatable, Sendable {
    var claimed = 0
    var delivered = 0
    var pausedForReconnect = false
}

actor DeliveryEngine {
    private let repository: CaptureRepository
    private let transport: any CaptureDeliveryTransport
    private let clock: any CaptureClock
    private let retryPolicy: RetryPolicy
    private var isDraining = false
    private var didPerformStartupRecovery = false

    init(
        repository: CaptureRepository,
        transport: any CaptureDeliveryTransport,
        clock: any CaptureClock = SystemCaptureClock(),
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.repository = repository
        self.transport = transport
        self.clock = clock
        self.retryPolicy = retryPolicy
    }

    func recoverInterruptedWork() async throws -> Int {
        didPerformStartupRecovery = true
        return try await repository.recoverInterruptedWork(at: clock.now())
    }

    func drain() async throws -> DeliveryDrainSummary {
        guard !isDraining else { return DeliveryDrainSummary() }
        isDraining = true
        defer { isDraining = false }

        if !didPerformStartupRecovery {
            didPerformStartupRecovery = true
            _ = try await repository.recoverInterruptedWork(at: clock.now())
        }

        var summary = DeliveryDrainSummary()
        while let record = try await repository.claimNext(at: clock.now(), retryPolicy: retryPolicy) {
            summary.claimed += 1
            do {
                let receipt = try await deliver(record)
                _ = try await repository.markDelivered(recordID: record.id, receipt: receipt, at: clock.now())
                summary.delivered += 1
            } catch let error as DeliveryTransportError {
                let paused = try await handle(error, for: record)
                summary.pausedForReconnect = summary.pausedForReconnect || paused
            } catch {
                let fallback = DeliveryTransportError.transport(message: nil)
                let paused = try await handle(fallback, for: record)
                summary.pausedForReconnect = summary.pausedForReconnect || paused
            }
        }
        return summary
    }

    private func deliver(_ record: CaptureRecordSnapshot) async throws -> DeliveryReceipt {
        switch record.destination {
        case let .managed(databaseID):
            if record.requiresManagedCheck,
               let existing = try await transport.findManagedCapture(
                   captureID: record.id,
                   databaseID: databaseID
               ) {
                return existing
            }
            return try await transport.createManaged(record, databaseID: databaseID)
        case let .manual(pageID):
            return try await transport.appendManual(record, pageID: pageID)
        }
    }

    private func handle(
        _ error: DeliveryTransportError,
        for record: CaptureRecordSnapshot
    ) async throws -> Bool {
        let now = clock.now()
        switch error {
        case let .http(status, retryAfter, _):
            if status == 401 {
                _ = try await repository.markRetrying(
                    recordID: record.id,
                    nextAttemptAt: nil,
                    requiresManagedCheck: record.destination.isManaged,
                    safeError: safeError(
                        code: "unauthorized",
                        message: "Reconnect to continue delivery.",
                        status: status,
                        retryAfter: retryAfter
                    ),
                    at: now
                )
                return true
            }
            if status == 409 {
                _ = try await repository.markBlockedConflict(
                    recordID: record.id,
                    safeError: safeError(
                        code: "conflict",
                        message: "Remote content changed and needs review.",
                        status: status,
                        retryAfter: retryAfter
                    ),
                    at: now
                )
                return false
            }
            if status == 429 {
                let delay = retryPolicy.delay(forAttempt: record.attemptCount, retryAfter: retryAfter)
                _ = try await repository.markRetrying(
                    recordID: record.id,
                    nextAttemptAt: now.addingTimeInterval(delay),
                    requiresManagedCheck: record.requiresManagedCheck,
                    safeError: safeError(
                        code: "rateLimited",
                        message: "Delivery was rate limited.",
                        status: status,
                        retryAfter: retryAfter
                    ),
                    at: now
                )
                return false
            }
            if status == 408 || (500 ... 599).contains(status) {
                return try await handleAmbiguous(
                    record: record,
                    status: status,
                    code: "ambiguousHTTP"
                )
            }
            _ = try await repository.markUncertain(
                recordID: record.id,
                safeError: safeError(
                    code: "httpFailure",
                    message: "Delivery failed and needs review.",
                    status: status,
                    retryAfter: retryAfter
                ),
                at: now
            )
            return false
        case .ambiguous:
            return try await handleAmbiguous(record: record, status: nil, code: "ambiguousTransport")
        case .transport:
            return try await handleAmbiguous(record: record, status: nil, code: "transportFailure")
        }
    }

    private func handleAmbiguous(
        record: CaptureRecordSnapshot,
        status: Int?,
        code: String
    ) async throws -> Bool {
        let now = clock.now()
        if record.destination.isManaged {
            let delay = retryPolicy.delay(forAttempt: record.attemptCount)
            _ = try await repository.markRetrying(
                recordID: record.id,
                nextAttemptAt: now.addingTimeInterval(delay),
                requiresManagedCheck: true,
                safeError: safeError(
                    code: code,
                    message: "Checking Capture ID before retrying managed delivery.",
                    status: status,
                    retryAfter: nil
                ),
                at: now
            )
        } else {
            _ = try await repository.markUncertain(
                recordID: record.id,
                safeError: safeError(
                    code: "ambiguousManualAppend",
                    message: "Manual append outcome needs review.",
                    status: status,
                    retryAfter: nil
                ),
                at: now
            )
        }
        return false
    }

    private func safeError(
        code: String,
        message: String,
        status: Int?,
        retryAfter: TimeInterval?
    ) -> SafeDeliveryError {
        SafeDeliveryError(
            code: code,
            message: message,
            statusCode: status,
            retryAfter: retryAfter
        )
    }
}
