import AppKit

enum SpaceTransitionEvent: Equatable, Sendable {
    case gestureHint(SpaceTransitionDirection)
    case activeSpaceDidChange(SpaceTransitionDirection?)
}

/// A direction hint read from a key or swipe event, before any task is spawned.
struct SpaceTransitionHint: Equatable, Sendable {
    var direction: SpaceTransitionDirection
    /// Control-arrow hints start the departure animation right away; swipe
    /// hints only supply direction for the Space change that follows.
    var publishes: Bool
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
            // Filter before spawning a task so ordinary typing costs nothing.
            if let hint = Self.hint(from: event) {
                Task { @MainActor [weak self] in
                    self?.recordHint(hint.direction, publishes: hint.publishes)
                }
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.swipe]
        ) { [weak self] event in
            if let hint = Self.hint(from: event) {
                Task { @MainActor [weak self] in
                    self?.recordHint(hint.direction, publishes: hint.publishes)
                }
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

    nonisolated static func hint(from event: NSEvent) -> SpaceTransitionHint? {
        switch event.type {
        case .keyDown:
            return keyHint(modifierFlags: event.modifierFlags, keyCode: event.keyCode)
        case .swipe:
            return swipeHint(deltaX: event.deltaX)
        default:
            return nil
        }
    }

    nonisolated static func keyHint(
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> SpaceTransitionHint? {
        guard modifierFlags.contains(.control),
            !modifierFlags.contains(.command),
            !modifierFlags.contains(.option),
            let direction = SpaceTransitionMotionPolicy.direction(forKeyCode: keyCode)
        else {
            return nil
        }
        return SpaceTransitionHint(direction: direction, publishes: true)
    }

    nonisolated static func swipeHint(deltaX: CGFloat) -> SpaceTransitionHint? {
        SpaceTransitionMotionPolicy.direction(forSwipeDeltaX: deltaX).map {
            SpaceTransitionHint(direction: $0, publishes: false)
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
