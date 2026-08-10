import AppKit

@MainActor
protocol DisplayTopologyObserving: AnyObject {
    var currentTopology: DisplayTopology { get }
    func start(_ handler: @escaping @MainActor (DisplayTopology) -> Void)
    func stop()
}

@MainActor
final class AppKitDisplayTopologyObserver: DisplayTopologyObserving {
    private let notificationCenter: NotificationCenter
    private let notificationName: Notification.Name
    private let displaysProvider: @MainActor () -> [DisplayDescriptor]
    private var notificationObserver: NSObjectProtocol?
    private var handler: (@MainActor (DisplayTopology) -> Void)?
    private(set) var currentTopology: DisplayTopology

    init(
        notificationCenter: NotificationCenter = .default,
        notificationName: Notification.Name = NSApplication.didChangeScreenParametersNotification,
        displaysProvider: @escaping @MainActor () -> [DisplayDescriptor] = {
            NSScreen.screens.enumerated().map { index, screen in
                let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
                let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber
                return DisplayDescriptor(
                    identifier: screenNumber?.uint32Value,
                    frame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    backingScaleFactor: screen.backingScaleFactor,
                    isPrimary: index == 0
                )
            }
        }
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.displaysProvider = displaysProvider
        currentTopology = DisplayTopology(revision: 0, displays: displaysProvider())
    }

    func start(_ handler: @escaping @MainActor (DisplayTopology) -> Void) {
        stop()
        self.handler = handler
        notificationObserver = notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishCurrentTopology()
            }
        }
    }

    func stop() {
        if let notificationObserver {
            notificationCenter.removeObserver(notificationObserver)
        }
        notificationObserver = nil
        handler = nil
    }

    isolated deinit {
        if let notificationObserver {
            notificationCenter.removeObserver(notificationObserver)
        }
    }

    private func publishCurrentTopology() {
        currentTopology = DisplayTopology(
            revision: currentTopology.revision &+ 1,
            displays: displaysProvider()
        )
        handler?(currentTopology)
    }
}
