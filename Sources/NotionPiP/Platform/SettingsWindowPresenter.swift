@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show()
}

@MainActor
final class SettingsWindowPresenter: SettingsWindowPresenting {
    private let makeWindowPresenter: @MainActor () -> any AppWindowPresenting
    private var windowPresenter: (any AppWindowPresenting)?

    init(windowPresenter: any AppWindowPresenting) {
        makeWindowPresenter = { windowPresenter }
        self.windowPresenter = windowPresenter
    }

    init(makeWindowPresenter: @escaping @MainActor () -> any AppWindowPresenting) {
        self.makeWindowPresenter = makeWindowPresenter
    }

    func show() {
        if let windowPresenter {
            windowPresenter.show()
            return
        }
        let windowPresenter = makeWindowPresenter()
        self.windowPresenter = windowPresenter
        windowPresenter.show()
    }
}
