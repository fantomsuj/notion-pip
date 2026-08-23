import AppKit

enum SpaceTransitionEvent: Equatable, Sendable {
    case gestureHint(SpaceTransitionDirection)
    case activeSpaceDidChange(SpaceTransitionDirection?)
}

@MainActor
protocol SpaceTransitionObserving: AnyObject {
    func start(_ handler: @escaping @MainActor (SpaceTransitionEvent) -> Void)
    func stop()
}

/// Observes public Space-change notifications and best-effort gesture hints.
///
/// `NSWorkspace.activeSpaceDidChangeNotification` is the source of truth.
/// Control-arrow and swipe monitors only supply travel direction and an early
/// hide hint; they are not required for the overlay to reappear.
@MainActor
final class AppKitSpaceTransitionObserver: SpaceTransitionObserving {
    private let notificationCenter: NotificationCenter
    private let notificationName: Notification.Name
    private let nowProvider: @MainActor () -> TimeInterval
    private let installsEventMonitors: Bool
    private var notificationObserver: NSObjectProtocol?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var handler: (@MainActor (SpaceTransitionEvent) -> Void)?
    private var hint: (direction: SpaceTransitionDirection, recordedAt: TimeInterval)?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        notificationName: Notification.Name = NSWorkspace.activeSpaceDidChangeNotification,
        nowProvider: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        installsEventMonitors: Bool = true
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.nowProvider = nowProvider
        self.installsEventMonitors = installsEventMonitors
    }

    func start(_ handler: @escaping @MainActor (SpaceTransitionEvent) -> Void) {
        stop()
        self.handler = handler
        notificationObserver = notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishSpaceDidChange()
            }
        }
        guard installsEventMonitors else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .swipe]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.recordHint(from: event)
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.swipe]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.recordHint(from: event)
            }
        }
    }

    func stop() {
        if let notificationObserver {
            notificationCenter.removeObserver(notificationObserver)
        }
        notificationObserver = nil
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        localEventMonitor = nil
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        globalEventMonitor = nil
        handler = nil
        hint = nil
    }

    func recordHint(
        _ direction: SpaceTransitionDirection,
        at now: TimeInterval? = nil,
        publishes: Bool = true
    ) {
        hint = (direction, now ?? nowProvider())
        guard publishes else { return }
        handler?(.gestureHint(direction))
    }

    isolated deinit {
        if let notificationObserver {
            notificationCenter.removeObserver(notificationObserver)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }

    private func recordHint(from event: NSEvent) {
        if event.type == .keyDown {
            guard event.modifierFlags.contains(.control),
                !event.modifierFlags.contains(.command),
                !event.modifierFlags.contains(.option),
                let direction = SpaceTransitionMotionPolicy.direction(forKeyCode: event.keyCode)
            else {
                return
            }
            recordHint(direction)
            return
        }
        if event.type == .swipe,
            let direction = SpaceTransitionMotionPolicy.direction(forSwipeDeltaX: event.deltaX)
        {
            recordHint(direction, publishes: false)
        }
    }

    private func publishSpaceDidChange() {
        let direction = SpaceTransitionMotionPolicy.resolvedDirection(
            hint: hint,
            now: nowProvider()
        )
        hint = nil
        handler?(.activeSpaceDidChange(direction))
    }
}
