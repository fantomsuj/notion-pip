import Foundation
import OSLog

typealias DeliveryRetentionOperation = @Sendable (Date) async throws -> RetentionResult

struct DeliverySchedulerHealthSnapshot: Equatable, Sendable {
    let hasDeliveryFailure: Bool
    let hasRetentionFailure: Bool
}

actor DeliveryScheduler {
    private static let maximumRecoveryRetryDelay: TimeInterval = 60
    private static let maximumRetentionRetryDelay: TimeInterval = 6 * 60 * 60

    private let logger = Logger(
        subsystem: "com.fantomsuj.NotionPiP",
        category: "delivery"
    )
    private let repository: CaptureRepository
    private let engine: DeliveryEngine
    private let clock: any CaptureClock
    private let recoveryRetryDelay: TimeInterval
    private let retentionStartupDelay: TimeInterval
    private let retentionInterval: TimeInterval
    private let retentionRetryDelay: TimeInterval
    private let retentionOperation: DeliveryRetentionOperation
    private var retryTask: Task<Void, Never>?
    private var retentionTask: Task<Void, Never>?
    private var needsUnauthorizedResumption = false
    private var didScheduleStartupRetention = false
    private var isTriggering = false
    private var triggerRequested = false
    private var hasDeliveryFailure = false
    private var hasRetentionFailure = false

    init(
        repository: CaptureRepository,
        engine: DeliveryEngine,
        clock: any CaptureClock = SystemCaptureClock(),
        recoveryRetryDelay: TimeInterval = 5,
        retentionStartupDelay: TimeInterval = 1,
        retentionInterval: TimeInterval = 24 * 60 * 60,
        retentionRetryDelay: TimeInterval = 60 * 60,
        retentionPolicy: RetentionPolicy = RetentionPolicy(),
        retentionOperation: DeliveryRetentionOperation? = nil
    ) {
        self.repository = repository
        self.engine = engine
        self.clock = clock
        self.recoveryRetryDelay = min(
            max(0.01, recoveryRetryDelay),
            Self.maximumRecoveryRetryDelay
        )
        self.retentionStartupDelay = max(0.01, retentionStartupDelay)
        self.retentionInterval = max(0.01, retentionInterval)
        self.retentionRetryDelay = min(
            max(0.01, retentionRetryDelay),
            Self.maximumRetentionRetryDelay
        )
        self.retentionOperation = retentionOperation ?? { date in
            try await repository.applyRetention(at: date, policy: retentionPolicy)
        }
    }

    func trigger(reconnected: Bool = false) async {
        if reconnected {
            needsUnauthorizedResumption = true
        }
        guard !isTriggering else {
            triggerRequested = true
            return
        }
        isTriggering = true
        defer { isTriggering = false }
        repeat {
            triggerRequested = false
            await performTrigger()
        } while triggerRequested
    }

    private func performTrigger() async {
        retryTask?.cancel()
        retryTask = nil

        var encounteredFailure = false
        if needsUnauthorizedResumption {
            do {
                _ = try await repository.resumeUnauthorizedRetries(at: clock.now())
                needsUnauthorizedResumption = false
            } catch {
                encounteredFailure = true
                recordDeliveryFailure(operation: "resume-unauthorized", error: error)
            }
        }

        do {
            _ = try await engine.drain()
        } catch {
            encounteredFailure = true
            recordDeliveryFailure(operation: "drain", error: error)
        }

        let scheduledRetryDelay: TimeInterval?
        do {
            scheduledRetryDelay = try await nextRetryDelay()
        } catch {
            encounteredFailure = true
            scheduledRetryDelay = nil
            recordDeliveryFailure(operation: "read-retry-metadata", error: error)
        }

        if encounteredFailure {
            hasDeliveryFailure = true
            scheduleRetry(after: min(scheduledRetryDelay ?? .infinity, recoveryRetryDelay))
        } else {
            hasDeliveryFailure = false
            if let scheduledRetryDelay {
                scheduleRetry(after: scheduledRetryDelay)
            }
            scheduleStartupRetentionIfNeeded()
        }
    }

    func healthSnapshot() -> DeliverySchedulerHealthSnapshot {
        DeliverySchedulerHealthSnapshot(
            hasDeliveryFailure: hasDeliveryFailure,
            hasRetentionFailure: hasRetentionFailure
        )
    }

    private func nextRetryDelay() async throws -> TimeInterval? {
        let nextAttempt = try await repository.records()
            .filter { $0.state == .retrying }
            .compactMap(\.nextAttemptAt)
            .min()
        return nextAttempt.map { max(0, $0.timeIntervalSince(clock.now())) }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, delay)))
            } catch is CancellationError {
                return
            } catch {
                await self?.handleSleepFailure()
                return
            }
            guard !Task.isCancelled else { return }
            await self?.trigger()
        }
    }

    private func scheduleStartupRetentionIfNeeded() {
        guard !didScheduleStartupRetention else { return }
        didScheduleStartupRetention = true
        scheduleRetention(after: retentionStartupDelay)
    }

    private func scheduleRetention(after delay: TimeInterval) {
        retentionTask?.cancel()
        retentionTask = Task(priority: .utility) { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, delay)))
            } catch is CancellationError {
                return
            } catch {
                await self?.handleRetentionSleepFailure()
                return
            }
            guard !Task.isCancelled else { return }
            await self?.runRetention()
        }
    }

    private func runRetention() async {
        do {
            let result = try await retentionOperation(clock.now())
            hasRetentionFailure = false
            logger.notice(
                "Capture retention completed deleted_records=\(result.deletedRecords, privacy: .public) deleted_drafts=\(result.deletedDrafts, privacy: .public)"
            )
            scheduleRetention(after: retentionInterval)
        } catch is CancellationError {
            return
        } catch {
            hasRetentionFailure = true
            logger.error(
                "Capture retention failed operation=apply-retention category=persistence"
            )
            scheduleRetention(after: retentionRetryDelay)
        }
    }

    private func handleRetentionSleepFailure() {
        hasRetentionFailure = true
        logger.error(
            "Capture retention failed operation=sleep category=unexpected"
        )
        scheduleRetention(after: retentionRetryDelay)
    }

    private func handleSleepFailure() {
        hasDeliveryFailure = true
        logger.error(
            "Delivery scheduler operation failed operation=sleep category=unexpected"
        )
        scheduleRetry(after: recoveryRetryDelay)
    }

    private func recordDeliveryFailure(operation: String, error: Error) {
        let category = error is CancellationError ? "cancelled" : "persistence"
        logger.error(
            "Delivery scheduler operation failed operation=\(operation, privacy: .public) category=\(category, privacy: .public)"
        )
    }
}
