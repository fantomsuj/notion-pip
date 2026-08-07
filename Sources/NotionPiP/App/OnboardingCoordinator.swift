@MainActor
final class OnboardingCoordinator {
    static let currentVersion = 1

    typealias WindowPresenterFactory = @MainActor (
        @escaping @MainActor () -> Void,
        @escaping @MainActor () -> Void
    ) -> any AppWindowPresenting

    private let preferenceStore: OnboardingPreferenceStore
    private weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private let makeWindowPresenter: WindowPresenterFactory
    private var windowPresenter: (any AppWindowPresenting)?

    init(
        preferenceStore: OnboardingPreferenceStore = OnboardingPreferenceStore(),
        settingsWindowPresenter: any SettingsWindowPresenting,
        makeWindowPresenter: @escaping WindowPresenterFactory
    ) {
        self.preferenceStore = preferenceStore
        self.settingsWindowPresenter = settingsWindowPresenter
        self.makeWindowPresenter = makeWindowPresenter
    }

    func showIfNeeded() {
        guard preferenceStore.shouldPresent(version: Self.currentVersion) else { return }
        show()
    }

    func show() {
        presenterOrCreate().show()
    }

    private func complete() {
        preferenceStore.markCompleted(version: Self.currentVersion)
        windowPresenter?.hide()
    }

    private func openSettings() {
        complete()
        settingsWindowPresenter?.show()
    }

    private func presenterOrCreate() -> any AppWindowPresenting {
        if let windowPresenter {
            return windowPresenter
        }
        let windowPresenter = makeWindowPresenter(
            { [weak self] in self?.complete() },
            { [weak self] in self?.openSettings() }
        )
        self.windowPresenter = windowPresenter
        return windowPresenter
    }
}
