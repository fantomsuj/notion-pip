import AppKit

@MainActor
protocol AppWindow: AnyObject {
    var isVisible: Bool { get }
    func presentAsKey()
    func orderOut()
}

@MainActor
protocol AppWindowPresenting: AnyObject {
    func show()
    func hide()
}

@MainActor
protocol AppWindowResourceDisposing: AnyObject {
    func disposeResources()
}

@MainActor
protocol ApplicationTerminationParticipating: AnyObject {
    func prepareForTermination() async -> Bool
}

@MainActor
final class LazyAppWindowPresenter: AppWindowPresenting {
    typealias ReleaseCancellation = @MainActor () -> Void
    typealias ReleaseScheduler = @MainActor (
        TimeInterval,
        @escaping @MainActor () -> Void
    ) -> ReleaseCancellation

    private let makePresenter: @MainActor () -> any AppWindowPresenting
    private let performanceSignposter: (any PerformanceSignposting)?
    private let firstPresentationOperation: PerformanceOperation?
    private let releaseScheduler: ReleaseScheduler
    private var presenter: (any AppWindowPresenting)?
    private var scheduledReleaseID: UUID?
    private var cancelScheduledRelease: ReleaseCancellation?
    private var didAttemptFirstPresentation = false

    init(
        makePresenter: @escaping @MainActor () -> any AppWindowPresenting,
        performanceSignposter: (any PerformanceSignposting)? = nil,
        firstPresentationOperation: PerformanceOperation? = nil,
        releaseScheduler: @escaping ReleaseScheduler = { delay, action in
            let task = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                action()
            }
            return { task.cancel() }
        }
    ) {
        self.makePresenter = makePresenter
        self.performanceSignposter = performanceSignposter
        self.firstPresentationOperation = firstPresentationOperation
        self.releaseScheduler = releaseScheduler
    }

    func show() {
        cancelPendingRelease()
        guard !didAttemptFirstPresentation,
              let performanceSignposter,
              let firstPresentationOperation
        else {
            presenterOrCreate().show()
            return
        }

        didAttemptFirstPresentation = true
        let token = performanceSignposter.begin(firstPresentationOperation)
        presenterOrCreate().show()
        performanceSignposter.end(token, outcome: .success)
    }

    func hide() {
        presenter?.hide()
    }

    func scheduleReleaseAfterSuccessfulClose() {
        guard presenter != nil else { return }

        cancelPendingRelease()
        let releaseID = UUID()
        scheduledReleaseID = releaseID
        cancelScheduledRelease = releaseScheduler(60) { [weak self] in
            guard let self, self.scheduledReleaseID == releaseID else { return }
            self.cancelScheduledRelease = nil
            self.scheduledReleaseID = nil
            self.releaseCurrentPresenter()
        }
    }

    var terminationParticipant: (any ApplicationTerminationParticipating)? {
        presenter as? any ApplicationTerminationParticipating
    }

    private func presenterOrCreate() -> any AppWindowPresenting {
        if let presenter {
            return presenter
        }

        let presenter = makePresenter()
        self.presenter = presenter
        return presenter
    }

    private func cancelPendingRelease() {
        cancelScheduledRelease?()
        cancelScheduledRelease = nil
        scheduledReleaseID = nil
    }

    private func releaseCurrentPresenter() {
        guard let presenter else { return }
        (presenter as? any AppWindowResourceDisposing)?.disposeResources()
        self.presenter = nil
    }
}

@MainActor
final class AppWindowPresenter: AppWindowPresenting,
    AppWindowResourceDisposing,
    ApplicationTerminationParticipating
{
    private let window: any AppWindow
    private let performanceSignposter: (any PerformanceSignposting)?
    private let firstPresentationOperation: PerformanceOperation?
    private let terminationHandler: (@MainActor () async -> Bool)?
    private var resourceDisposalHandler: (@MainActor () -> Void)?
    private var didAttemptFirstPresentation = false

    init(
        window: any AppWindow,
        performanceSignposter: (any PerformanceSignposting)? = nil,
        firstPresentationOperation: PerformanceOperation? = nil,
        terminationHandler: (@MainActor () async -> Bool)? = nil,
        resourceDisposalHandler: (@MainActor () -> Void)? = nil
    ) {
        self.window = window
        self.performanceSignposter = performanceSignposter
        self.firstPresentationOperation = firstPresentationOperation
        self.terminationHandler = terminationHandler
        self.resourceDisposalHandler = resourceDisposalHandler
    }

    func show() {
        guard !didAttemptFirstPresentation,
              let performanceSignposter,
              let firstPresentationOperation
        else {
            window.presentAsKey()
            return
        }

        didAttemptFirstPresentation = true
        let token = performanceSignposter.begin(firstPresentationOperation)
        window.presentAsKey()
        performanceSignposter.end(token, outcome: .success)
    }

    func hide() {
        window.orderOut()
    }

    func prepareForTermination() async -> Bool {
        guard window.isVisible, let terminationHandler else { return true }
        return await terminationHandler()
    }

    func disposeResources() {
        resourceDisposalHandler?()
        resourceDisposalHandler = nil
    }
}

final class KeyCapableAppWindow: NSWindow, AppWindow {
    var closeRequestHandler: (@MainActor () -> Void)?
    var isProcessingCloseRequest = false

    override var canBecomeKey: Bool {
        true
    }

    override func close() {
        if let closeRequestHandler {
            closeRequestHandler()
        } else {
            orderOut(nil)
        }
    }

    func presentAsKey() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }
}
