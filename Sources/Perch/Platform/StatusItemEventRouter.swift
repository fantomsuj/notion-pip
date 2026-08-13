import AppKit

@MainActor
final class StatusItemEventRouter {
    private let holdDuration: Duration
    private let scheduler: any ShortcutGestureScheduling
    private let onMenu: () -> Void
    private let onBeginPeek: () -> Bool
    private let onCommitPeek: () -> Void
    private let onCancelPeek: () -> Void

    private var phase: StatusItemPointerPhase = .idle
    private var holdTimer: (any ShortcutGestureTimer)?

    init(
        holdDuration: Duration = .milliseconds(300),
        scheduler: any ShortcutGestureScheduling = TaskShortcutGestureScheduler(),
        onMenu: @escaping () -> Void,
        onBeginPeek: @escaping () -> Bool = { false },
        onCommitPeek: @escaping () -> Void = {},
        onCancelPeek: @escaping () -> Void = {}
    ) {
        self.holdDuration = holdDuration
        self.scheduler = scheduler
        self.onMenu = onMenu
        self.onBeginPeek = onBeginPeek
        self.onCommitPeek = onCommitPeek
        self.onCancelPeek = onCancelPeek
    }

    func handle(eventType: NSEvent.EventType, isPointerInside: Bool = true) {
        let event: StatusItemPointerEvent
        switch eventType {
        case .leftMouseDown:
            event = .leftMouseDown
        case .leftMouseUp:
            event = .leftMouseUp(isPointerInside: isPointerInside)
        case .rightMouseUp:
            event = .rightMouseUp
        default:
            return
        }
        apply(event)
    }

    private func apply(_ event: StatusItemPointerEvent) {
        let (nextPhase, commands) = StatusItemPointerPolicy.handle(
            phase: phase,
            event: event
        )
        if !commands.contains(.beginHold) {
            cancelHoldTimer()
        }

        var appliedPhase = nextPhase
        for command in commands {
            switch command {
            case .beginHold:
                startHoldTimer()
            case .beginPeek:
                if !onBeginPeek() {
                    appliedPhase = .holding
                }
            case .commitPeek:
                onCommitPeek()
            case .cancelPeek:
                onCancelPeek()
            case .showMenu:
                onMenu()
            }
        }
        phase = appliedPhase
    }

    private func startHoldTimer() {
        holdTimer?.cancel()
        holdTimer = scheduler.schedule(after: holdDuration) { [weak self] in
            self?.apply(.holdElapsed)
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }
}
