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
final class LazyAppWindowPresenter: AppWindowPresenting {
    private let makePresenter: @MainActor () -> any AppWindowPresenting
    private let performanceSignposter: (any PerformanceSignposting)?
    private let firstPresentationOperation: PerformanceOperation?
    private var presenter: (any AppWindowPresenting)?
    private var didAttemptFirstPresentation = false

    init(
        makePresenter: @escaping @MainActor () -> any AppWindowPresenting,
        performanceSignposter: (any PerformanceSignposting)? = nil,
        firstPresentationOperation: PerformanceOperation? = nil
    ) {
        self.makePresenter = makePresenter
        self.performanceSignposter = performanceSignposter
        self.firstPresentationOperation = firstPresentationOperation
    }

    func show() {
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

    private func presenterOrCreate() -> any AppWindowPresenting {
        if let presenter {
            return presenter
        }

        let presenter = makePresenter()
        self.presenter = presenter
        return presenter
    }
}

@MainActor
final class AppWindowPresenter: AppWindowPresenting {
    private let window: any AppWindow
    private let performanceSignposter: (any PerformanceSignposting)?
    private let firstPresentationOperation: PerformanceOperation?
    private var didAttemptFirstPresentation = false

    init(
        window: any AppWindow,
        performanceSignposter: (any PerformanceSignposting)? = nil,
        firstPresentationOperation: PerformanceOperation? = nil
    ) {
        self.window = window
        self.performanceSignposter = performanceSignposter
        self.firstPresentationOperation = firstPresentationOperation
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
}

final class KeyCapableAppWindow: NSWindow, AppWindow {
    override var canBecomeKey: Bool {
        true
    }

    override func close() {
        orderOut(nil)
    }

    func presentAsKey() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func orderOut() {
        orderOut(nil)
    }
}
