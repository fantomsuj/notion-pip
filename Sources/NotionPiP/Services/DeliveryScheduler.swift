import Foundation

actor DeliveryScheduler {
    private let repository: CaptureRepository
    private let engine: DeliveryEngine
    private let clock: any CaptureClock
    private var retryTask: Task<Void, Never>?

    init(
        repository: CaptureRepository,
        engine: DeliveryEngine,
        clock: any CaptureClock = SystemCaptureClock()
    ) {
        self.repository = repository
        self.engine = engine
        self.clock = clock
    }

    func trigger(reconnected: Bool = false) async {
        retryTask?.cancel()
        retryTask = nil
        if reconnected {
            _ = try? await repository.resumeUnauthorizedRetries(at: clock.now())
        }
        _ = try? await engine.drain()
        await scheduleNextRetry()
    }

    private func scheduleNextRetry() async {
        guard let records = try? await repository.records(),
              let nextAttempt = records
            .filter({ $0.state == .retrying })
            .compactMap(\.nextAttemptAt)
            .min()
        else {
            return
        }
        let delay = max(0, nextAttempt.timeIntervalSince(clock.now()))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.trigger()
        }
    }
}
