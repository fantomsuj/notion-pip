import Foundation
import XCTest
@testable import Perch

@MainActor
final class ShortcutLifecycleCoordinatorTests: XCTestCase {
    func testWakeAndSessionBurstCoalescesToOneRecovery() {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.post(.testDidWake)
        harness.post(.testScreensDidWake)
        harness.post(.testSessionDidBecomeActive)

        XCTAssertEqual(harness.scheduler.activeCount, 1)
        harness.scheduler.runNextActive()
        XCTAssertEqual(harness.recoveryCount(), 1)
    }

    func testExplicitRetryCoalescesWithPendingLifecycleRecovery() {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.post(.testDidWake)
        harness.coordinator.requestRetry()

        XCTAssertEqual(harness.scheduler.activeCount, 1)
        harness.scheduler.runNextActive()
        XCTAssertEqual(harness.recoveryCount(), 1)
    }

    func testSettingsInvalidationDropsPendingRecovery() {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.post(.testDidWake)
        let pending = harness.scheduler.last

        harness.coordinator.invalidatePendingRecovery()
        pending?.runEvenIfCancelled()

        XCTAssertEqual(harness.recoveryCount(), 0)
        XCTAssertEqual(harness.scheduler.activeCount, 0)
    }

    func testStopRemovesObserversAndDropsPendingRecovery() {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.post(.testDidWake)
        let pending = harness.scheduler.last

        harness.coordinator.stop()
        pending?.runEvenIfCancelled()
        harness.post(.testSessionDidBecomeActive)

        XCTAssertEqual(harness.recoveryCount(), 0)
        XCTAssertEqual(harness.scheduler.activeCount, 0)
    }

    func testCapturedStaleCallbackCannotRunAfterNewerBurst() {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.post(.testDidWake)
        let stale = harness.scheduler.last
        harness.post(.testScreensDidWake)
        let current = harness.scheduler.last

        stale?.runEvenIfCancelled()
        XCTAssertEqual(harness.recoveryCount(), 0)

        current?.run()
        XCTAssertEqual(harness.recoveryCount(), 1)
    }

    private func makeHarness() -> ShortcutLifecycleHarness {
        ShortcutLifecycleHarness()
    }
}

@MainActor
private final class ShortcutLifecycleHarness {
    let center = NotificationCenter()
    let scheduler = ShortcutRecoverySchedulerSpy()
    private var recoveries = 0
    lazy var coordinator = ShortcutLifecycleCoordinator(
        notificationCenter: center,
        notificationNames: [
            .testDidWake,
            .testScreensDidWake,
            .testSessionDidBecomeActive,
        ],
        scheduler: scheduler,
        onRecovery: { [weak self] _ in self?.recoveries += 1 }
    )

    func post(_ name: Notification.Name) {
        center.post(name: name, object: nil)
    }

    func recoveryCount() -> Int { recoveries }
}

private extension Notification.Name {
    static let testDidWake = Notification.Name("ShortcutLifecycleTests.didWake")
    static let testScreensDidWake = Notification.Name("ShortcutLifecycleTests.screensDidWake")
    static let testSessionDidBecomeActive = Notification.Name(
        "ShortcutLifecycleTests.sessionDidBecomeActive"
    )
}

@MainActor
private final class ShortcutRecoverySchedulerSpy: ShortcutRecoveryScheduling {
    private(set) var scheduled: [ScheduledShortcutRecovery] = []

    var last: ScheduledShortcutRecovery? { scheduled.last }
    var activeCount: Int { scheduled.count(where: { !$0.isCancelled && !$0.didRun }) }

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () -> Void
    ) -> any ShortcutRecoveryCancellation {
        let recovery = ScheduledShortcutRecovery(operation: operation)
        scheduled.append(recovery)
        return recovery
    }

    func runNextActive() {
        scheduled.first(where: { !$0.isCancelled && !$0.didRun })?.run()
    }
}

@MainActor
private final class ScheduledShortcutRecovery: ShortcutRecoveryCancellation {
    private let operation: @MainActor () -> Void
    private(set) var isCancelled = false
    private(set) var didRun = false

    init(operation: @escaping @MainActor () -> Void) {
        self.operation = operation
    }

    func cancel() {
        isCancelled = true
    }

    func run() {
        guard !isCancelled, !didRun else { return }
        runEvenIfCancelled()
    }

    func runEvenIfCancelled() {
        guard !didRun else { return }
        didRun = true
        operation()
    }
}
