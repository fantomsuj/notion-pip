import AppKit
import Foundation

enum ShortcutRecoveryTrigger: Equatable, Sendable {
    case lifecycleEvent
    case retry
}

@MainActor
protocol ShortcutRecoveryCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol ShortcutRecoveryScheduling: AnyObject {
    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () -> Void
    ) -> any ShortcutRecoveryCancellation
}

@MainActor
final class TaskShortcutRecoveryScheduler: ShortcutRecoveryScheduling {
    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () -> Void
    ) -> any ShortcutRecoveryCancellation {
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            operation()
        }
        return TaskShortcutRecoveryCancellation(task: task)
    }
}

@MainActor
private final class TaskShortcutRecoveryCancellation: ShortcutRecoveryCancellation {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

@MainActor
final class ShortcutLifecycleCoordinator {
    private let notificationCenter: NotificationCenter
    private let notificationNames: [Notification.Name]
    private let scheduler: any ShortcutRecoveryScheduling
    private let coalescingDelay: Duration
    private let onRecovery: @MainActor (ShortcutRecoveryTrigger) -> Void
    private var observers: [NSObjectProtocol] = []
    private var pendingRecovery: (any ShortcutRecoveryCancellation)?
    private var pendingTrigger: ShortcutRecoveryTrigger?
    private var generation: UInt = 0
    private var isStarted = false

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        notificationNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ],
        scheduler: any ShortcutRecoveryScheduling = TaskShortcutRecoveryScheduler(),
        coalescingDelay: Duration = .milliseconds(250),
        onRecovery: @escaping @MainActor (ShortcutRecoveryTrigger) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.notificationNames = notificationNames
        self.scheduler = scheduler
        self.coalescingDelay = coalescingDelay
        self.onRecovery = onRecovery
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observers = notificationNames.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRecovery(trigger: .lifecycleEvent)
                }
            }
        }
    }

    func requestRetry() {
        guard isStarted else { return }
        scheduleRecovery(trigger: .retry)
    }

    func invalidatePendingRecovery() {
        generation &+= 1
        pendingRecovery?.cancel()
        pendingRecovery = nil
        pendingTrigger = nil
    }

    func stop() {
        guard isStarted else {
            invalidatePendingRecovery()
            return
        }
        isStarted = false
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        invalidatePendingRecovery()
    }

    isolated deinit {
        observers.forEach(notificationCenter.removeObserver)
        pendingRecovery?.cancel()
    }

    private func scheduleRecovery(trigger: ShortcutRecoveryTrigger) {
        generation &+= 1
        let scheduledGeneration = generation
        let scheduledTrigger: ShortcutRecoveryTrigger =
            pendingTrigger == .lifecycleEvent ? .lifecycleEvent : trigger
        pendingRecovery?.cancel()
        pendingTrigger = scheduledTrigger
        pendingRecovery = scheduler.schedule(after: coalescingDelay) { [weak self] in
            guard let self,
                  self.isStarted,
                  self.generation == scheduledGeneration
            else { return }
            self.pendingRecovery = nil
            self.pendingTrigger = nil
            self.onRecovery(scheduledTrigger)
        }
    }
}
