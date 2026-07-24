@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show()
}

@MainActor
final class SettingsWindowPresenter: SettingsWindowPresenting {
    private let windowPresenter: any AppWindowPresenting

    init(windowPresenter: any AppWindowPresenting) {
        self.windowPresenter = windowPresenter
    }

    func show() {
        windowPresenter.show()
    }
}
