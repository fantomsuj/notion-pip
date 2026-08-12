import AppKit
import Foundation

@MainActor
protocol PeekFocusRestoring: AnyObject {
    func beginPeek()
    func finishPeek()
    func cancelPeek()
}

struct PeekFocusApplication {
    let processIdentifier: pid_t
    private let terminationState: @MainActor () -> Bool
    private let activation: @MainActor () -> Bool

    init(
        processIdentifier: pid_t,
        isTerminated: @escaping @MainActor () -> Bool,
        activate: @escaping @MainActor () -> Bool
    ) {
        self.processIdentifier = processIdentifier
        terminationState = isTerminated
        activation = activate
    }

    @MainActor
    var isTerminated: Bool {
        terminationState()
    }

    @MainActor
    @discardableResult
    func activate() -> Bool {
        activation()
    }
}

@MainActor
protocol PeekInteractionMonitoring: AnyObject {
    func start(onInteraction: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class PeekFocusRestorer: PeekFocusRestoring {
    private let currentProcessIdentifier: pid_t
    private let frontmostApplication: @MainActor () -> PeekFocusApplication?
    private let interactionMonitor: any PeekInteractionMonitoring
    private var previousApplication: PeekFocusApplication?
    private var didInteract = false

    init(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        frontmostApplication: @escaping @MainActor () -> PeekFocusApplication? = {
            NSWorkspace.shared.frontmostApplication.map { application in
                PeekFocusApplication(
                    processIdentifier: application.processIdentifier,
                    isTerminated: { application.isTerminated },
                    activate: { application.activate(options: []) }
                )
            }
        },
        interactionMonitor: any PeekInteractionMonitoring = LocalPeekInteractionMonitor()
    ) {
        self.currentProcessIdentifier = currentProcessIdentifier
        self.frontmostApplication = frontmostApplication
        self.interactionMonitor = interactionMonitor
    }

    func beginPeek() {
        if previousApplication != nil {
            cancelPeek()
        }
        guard let application = frontmostApplication(),
              application.processIdentifier != currentProcessIdentifier
        else {
            return
        }
        previousApplication = application
        didInteract = false
        interactionMonitor.start { [weak self] in
            self?.didInteract = true
        }
    }

    func finishPeek() {
        let application = previousApplication
        let shouldRestore = !didInteract
            && frontmostApplication()?.processIdentifier == currentProcessIdentifier
        cancelPeek()

        guard shouldRestore,
              let application,
              !application.isTerminated
        else {
            return
        }
        _ = application.activate()
    }

    func cancelPeek() {
        interactionMonitor.stop()
        previousApplication = nil
        didInteract = false
    }
}

@MainActor
private final class LocalPeekInteractionMonitor: PeekInteractionMonitoring {
    private var monitor: Any?

    func start(onInteraction: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .keyDown,
                .scrollWheel,
            ]
        ) { event in
            onInteraction()
            return event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
