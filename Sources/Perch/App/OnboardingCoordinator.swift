@MainActor
final class OnboardingCoordinator {
    static let currentVersion = 1

    typealias WindowPresenterFactory = @MainActor (
        @escaping @MainActor () -> Bool,
        @escaping @MainActor () -> Void,
        @escaping @MainActor () -> Void
    ) -> any AppWindowPresenting

    private let preferenceStore: OnboardingPreferenceStore
    private weak var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private let openCurrentPage: @MainActor () -> Bool
    private let onFinish: @MainActor () -> Void
    private let makeWindowPresenter: WindowPresenterFactory
    private var windowPresenter: (any AppWindowPresenting)?

    init(
        preferenceStore: OnboardingPreferenceStore = OnboardingPreferenceStore(),
        settingsWindowPresenter: any SettingsWindowPresenting,
        openCurrentPage: @escaping @MainActor () -> Bool,
        onFinish: @escaping @MainActor () -> Void,
        makeWindowPresenter: @escaping WindowPresenterFactory
    ) {
        self.preferenceStore = preferenceStore
        self.settingsWindowPresenter = settingsWindowPresenter
        self.openCurrentPage = openCurrentPage
        self.onFinish = onFinish
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
        finishCompletion()
    }

    private func finishCompletion() {
        onFinish()
        preferenceStore.markCompleted(version: Self.currentVersion)
        windowPresenter?.hide()
    }

    private func openSettings() {
        finishCompletion()
        settingsWindowPresenter?.show()
    }

    private func openPage() -> Bool {
        openCurrentPage()
    }

    private func presenterOrCreate() -> any AppWindowPresenting {
        if let windowPresenter {
            return windowPresenter
        }
        let windowPresenter = makeWindowPresenter(
            { [weak self] in self?.openPage() ?? false },
            { [weak self] in self?.complete() },
            { [weak self] in self?.openSettings() }
        )
        self.windowPresenter = windowPresenter
        return windowPresenter
    }
}
