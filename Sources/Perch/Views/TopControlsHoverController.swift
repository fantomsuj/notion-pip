import Foundation

typealias TopControlsHoverCancellation = @MainActor () -> Void
typealias TopControlsHoverScheduler = @MainActor (
    _ delay: Duration,
    _ operation: @escaping @MainActor () -> Void
) -> TopControlsHoverCancellation

@MainActor
final class TopControlsHoverController: ObservableObject {
    @Published private(set) var isHovering = false

    private let revealDelay: Duration
    private let dismissalDelay: Duration
    private let scheduler: TopControlsHoverScheduler
    private var cancelReveal: TopControlsHoverCancellation?
    private var cancelDismissal: TopControlsHoverCancellation?

    init(
        revealDelay: Duration = .milliseconds(250),
        dismissalDelay: Duration = .milliseconds(500),
        scheduler: @escaping TopControlsHoverScheduler = scheduleTopControlsHoverOperation
    ) {
        self.revealDelay = revealDelay
        self.dismissalDelay = dismissalDelay
        self.scheduler = scheduler
    }

    func setHovering(_ isHovering: Bool) {
        if isHovering {
            cancelDismissal?()
            cancelDismissal = nil

            guard !self.isHovering else { return }

            cancelReveal?()
            cancelReveal = scheduler(revealDelay) { [weak self] in
                self?.isHovering = true
            }
            return
        }

        cancelReveal?()
        cancelReveal = nil

        guard self.isHovering else { return }

        cancelDismissal?()
        cancelDismissal = scheduler(dismissalDelay) { [weak self] in
            self?.isHovering = false
        }
    }

    func cancel() {
        cancelReveal?()
        cancelReveal = nil
        cancelDismissal?()
        cancelDismissal = nil
        isHovering = false
    }
}

@MainActor
private func scheduleTopControlsHoverOperation(
    after delay: Duration,
    operation: @escaping @MainActor () -> Void
) -> TopControlsHoverCancellation {
    let task = Task { @MainActor in
        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        operation()
    }
    return { task.cancel() }
}
