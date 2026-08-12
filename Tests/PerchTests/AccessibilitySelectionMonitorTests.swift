import XCTest
@testable import Perch

@MainActor
final class AccessibilitySelectionMonitorTests: XCTestCase {
    func testKeyboardSelectionChangesDebounceToOneCommit() {
        let scheduler = QuickCopyCommitSchedulerSpy()
        var commitCount = 0
        let coordinator = QuickCopySelectionCommitCoordinator(
            keyboardDebounce: .milliseconds(250),
            schedule: scheduler.schedule,
            onCommit: { commitCount += 1 }
        )

        coordinator.selectedTextDidChange()
        scheduler.advance(by: .milliseconds(100))
        coordinator.selectedTextDidChange()
        scheduler.advance(by: .milliseconds(249))
        XCTAssertEqual(commitCount, 0)
        scheduler.advance(by: .milliseconds(1))

        XCTAssertEqual(commitCount, 1)
    }

    func testMouseReleaseCommitsImmediatelyAndCancelsKeyboardDuplicate() {
        let scheduler = QuickCopyCommitSchedulerSpy()
        var commitCount = 0
        let coordinator = QuickCopySelectionCommitCoordinator(
            schedule: scheduler.schedule,
            onCommit: { commitCount += 1 }
        )

        coordinator.selectedTextDidChange()
        coordinator.mouseDidRelease()
        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(commitCount, 1)
    }

    func testCancelDropsPendingKeyboardCommit() {
        let scheduler = QuickCopyCommitSchedulerSpy()
        var commitCount = 0
        let coordinator = QuickCopySelectionCommitCoordinator(
            schedule: scheduler.schedule,
            onCommit: { commitCount += 1 }
        )

        coordinator.selectedTextDidChange()
        coordinator.cancel()
        scheduler.advance(by: .seconds(1))

        XCTAssertEqual(commitCount, 0)
    }
}

@MainActor
private final class QuickCopyCommitSchedulerSpy {
    private final class CancellationState {
        var isCancelled = false
    }

    private struct ScheduledOperation {
        let deadline: Duration
        let cancellation: CancellationState
        let operation: @MainActor () -> Void
    }

    private var elapsed: Duration = .zero
    private var operations: [ScheduledOperation] = []

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () -> Void
    ) -> QuickCopyScheduledCancellation {
        let cancellation = CancellationState()
        operations.append(
            ScheduledOperation(
                deadline: elapsed + delay,
                cancellation: cancellation,
                operation: operation
            )
        )
        return { cancellation.isCancelled = true }
    }

    func advance(by duration: Duration) {
        elapsed += duration
        let ready = operations
            .filter { $0.deadline <= elapsed }
            .sorted { $0.deadline < $1.deadline }
        operations.removeAll { $0.deadline <= elapsed }
        for operation in ready where !operation.cancellation.isCancelled {
            operation.operation()
        }
    }
}
