@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show()
}

@MainActor
final class SettingsWindowPresenter: SettingsWindowPresenting {
    typealias CloseHandler = @MainActor () -> Void
    private let makeWindowPresenter: @MainActor (
        @escaping CloseHandler
    ) -> any AppWindowPresenting
    private var windowPresenter: (any AppWindowPresenting)?

    init(windowPresenter: any AppWindowPresenting) {
        makeWindowPresenter = { _ in windowPresenter }
        self.windowPresenter = windowPresenter
    }

    init(makeWindowPresenter: @escaping @MainActor () -> any AppWindowPresenting) {
        self.makeWindowPresenter = { _ in makeWindowPresenter() }
    }

    init(
        makeWindowPresenter: @escaping @MainActor (
            @escaping CloseHandler
        ) -> any AppWindowPresenting
    ) {
        self.makeWindowPresenter = makeWindowPresenter
    }

    func show() {
        if let windowPresenter {
            windowPresenter.show()
            return
        }
        let windowPresenter = makeWindowPresenter { [weak self] in
            self?.windowPresenter = nil
        }
        self.windowPresenter = windowPresenter
        windowPresenter.show()
    }
}
