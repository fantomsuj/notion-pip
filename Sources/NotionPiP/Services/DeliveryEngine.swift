import Foundation

struct DeliveryReceipt: Equatable, Sendable {
    let remoteIdentity: String
    let fingerprint: String?
}

enum DeliveryTransportError: Error, Equatable, Sendable {
    case http(status: Int, retryAfter: TimeInterval?, message: String?)
    case retryable(message: String?)
    case ambiguous(message: String?)
    case transport(message: String?)
}

protocol CaptureDeliveryTransport: Sendable {
    func findManagedCapture(captureID: String, databaseID: String) async throws -> DeliveryReceipt?
    func createManaged(_ record: CaptureRecordSnapshot, databaseID: String) async throws -> DeliveryReceipt
    func appendManual(_ record: CaptureRecordSnapshot, pageID: String) async throws -> DeliveryReceipt
    func createChildPage(_ record: CaptureRecordSnapshot, parentPageID: String) async throws -> DeliveryReceipt
    func createDataSourcePage(_ record: CaptureRecordSnapshot, dataSourceID: String) async throws -> DeliveryReceipt
}

extension CaptureDeliveryTransport {
    func createChildPage(
        _ record: CaptureRecordSnapshot,
        parentPageID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(message: "Child-page delivery is unavailable.")
    }

    func createDataSourcePage(
        _ record: CaptureRecordSnapshot,
        dataSourceID: String
    ) async throws -> DeliveryReceipt {
        throw DeliveryTransportError.transport(message: "Data-source delivery is unavailable.")
    }
}

typealias DeliveryStartupRecovery = @Sendable (Date) async throws -> Int

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
    private let startupRecovery: DeliveryStartupRecovery
    private var isDraining = false
    private var didPerformStartupRecovery = false

    init(
        repository: CaptureRepository,
        transport: any CaptureDeliveryTransport,
        clock: any CaptureClock = SystemCaptureClock(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        startupRecovery: DeliveryStartupRecovery? = nil
    ) {
        self.repository = repository
        self.transport = transport
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.startupRecovery = startupRecovery ?? { date in
            try await repository.recoverInterruptedWork(at: date)
        }
    }

    func recoverInterruptedWork() async throws -> Int {
        let recovered = try await startupRecovery(clock.now())
        didPerformStartupRecovery = true
        return recovered
    }

    func drain() async throws -> DeliveryDrainSummary {
        guard !isDraining else { return DeliveryDrainSummary() }
        isDraining = true
        var completed = false
        defer {
            isDraining = false
            if !completed {
                didPerformStartupRecovery = false
            }
        }

        if !didPerformStartupRecovery {
            _ = try await startupRecovery(clock.now())
            didPerformStartupRecovery = true
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
                if paused { break }
            } catch {
                let fallback = DeliveryTransportError.transport(message: nil)
                let paused = try await handle(fallback, for: record)
                summary.pausedForReconnect = summary.pausedForReconnect || paused
            }
        }
        completed = true
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
        case let .pageParent(pageID):
            return try await transport.createChildPage(record, parentPageID: pageID)
        case let .dataSource(dataSourceID):
            return try await transport.createDataSourcePage(record, dataSourceID: dataSourceID)
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
                if (500 ... 599).contains(status),
                   record.destination.isJournaledPageCreation
                {
                    return try await scheduleRetry(
                        record: record,
                        retryAfter: retryAfter,
                        code: "serverFailure",
                        message: "Notion could not accept the delivery yet.",
                        status: status
                    )
                }
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
        case let .retryable(message):
            return try await scheduleRetry(
                record: record,
                retryAfter: nil,
                code: "transportUnavailable",
                message: message ?? "Delivery will retry when the network is available.",
                status: nil
            )
        case .ambiguous:
            return try await handleAmbiguous(record: record, status: nil, code: "ambiguousTransport")
        case .transport:
            return try await handleAmbiguous(record: record, status: nil, code: "transportFailure")
        }
    }

    private func scheduleRetry(
        record: CaptureRecordSnapshot,
        retryAfter: TimeInterval?,
        code: String,
        message: String,
        status: Int?
    ) async throws -> Bool {
        let now = clock.now()
        let delay = retryPolicy.delay(
            forAttempt: record.attemptCount,
            retryAfter: retryAfter
        )
        _ = try await repository.markRetrying(
            recordID: record.id,
            nextAttemptAt: now.addingTimeInterval(delay),
            requiresManagedCheck: record.requiresManagedCheck,
            safeError: safeError(
                code: code,
                message: message,
                status: status,
                retryAfter: retryAfter
            ),
            at: now
        )
        return false
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
            let isPageCreation = record.destination.isJournaledPageCreation
            _ = try await repository.markUncertain(
                recordID: record.id,
                safeError: safeError(
                    code: isPageCreation
                        ? "ambiguousPageCreation"
                        : "ambiguousManualAppend",
                    message: isPageCreation
                        ? "Notion may have created this capture. Open the local copy to recover without creating a duplicate."
                        : "Manual append outcome needs review.",
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
