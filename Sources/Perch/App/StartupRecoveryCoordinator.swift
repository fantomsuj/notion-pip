@MainActor
final class StartupPresentationGate {
    private(set) var isRecoveryPending: Bool

    var allowsCompetingPresentation: Bool {
        !isRecoveryPending
    }

    init(recoveryRequired: Bool) {
        isRecoveryPending = recoveryRequired
    }

    @discardableResult
    func completeRecovery() -> Bool {
        guard isRecoveryPending else { return false }
        isRecoveryPending = false
        return true
    }
}

@MainActor
final class RecoveryGuardedSettingsWindowPresenter: SettingsWindowPresenting {
    private let presenter: any SettingsWindowPresenting
    private let gate: StartupPresentationGate

    init(
        presenter: any SettingsWindowPresenting,
        gate: StartupPresentationGate
    ) {
        self.presenter = presenter
        self.gate = gate
    }

    func show() {
        guard gate.allowsCompetingPresentation else { return }
        presenter.show()
    }
}

@MainActor
final class StartupRecoveryCoordinator {
    private let recoveryRequired: Bool
    private let gate: StartupPresentationGate
    private let recoveryPresenter: any AppWindowPresenting
    private let showOnboardingIfNeeded: @MainActor () -> Bool
    private let showCurrentPageSetup: @MainActor () -> Void

    init(
        recoveryRequired: Bool,
        gate: StartupPresentationGate,
        recoveryPresenter: any AppWindowPresenting,
        showOnboardingIfNeeded: @escaping @MainActor () -> Bool,
        showCurrentPageSetup: @escaping @MainActor () -> Void
    ) {
        self.recoveryRequired = recoveryRequired
        self.gate = gate
        self.recoveryPresenter = recoveryPresenter
        self.showOnboardingIfNeeded = showOnboardingIfNeeded
        self.showCurrentPageSetup = showCurrentPageSetup
    }

    func applicationDidFinishLaunching() {
        if recoveryRequired {
            recoveryPresenter.show()
        } else {
            _ = showOnboardingIfNeeded()
        }
    }

    func continueWithoutSaving() {
        guard gate.completeRecovery() else { return }
        recoveryPresenter.hide()
        if !showOnboardingIfNeeded() {
            showCurrentPageSetup()
        }
    }
}
