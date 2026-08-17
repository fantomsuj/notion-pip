import XCTest
@testable import Perch

@MainActor
final class StartupRecoveryCoordinationTests: XCTestCase {
    func testContinueResumesOnboardingAndReleasesSettingsGate() {
        let gate = StartupPresentationGate(recoveryRequired: true)
        let recoveryPresenter = StartupRecoveryWindowPresenterSpy()
        let settingsPresenter = StartupRecoverySettingsPresenterSpy()
        let guardedSettings = RecoveryGuardedSettingsWindowPresenter(
            presenter: settingsPresenter,
            gate: gate
        )
        var onboardingCount = 0
        var currentPageSetupCount = 0
        let coordinator = StartupRecoveryCoordinator(
            recoveryRequired: true,
            gate: gate,
            recoveryPresenter: recoveryPresenter,
            showOnboardingIfNeeded: {
                onboardingCount += 1
                return true
            },
            showCurrentPageSetup: { currentPageSetupCount += 1 }
        )
        coordinator.applicationDidFinishLaunching()

        coordinator.continueWithoutSaving()
        guardedSettings.show()

        XCTAssertEqual(recoveryPresenter.hideCount, 1)
        XCTAssertEqual(onboardingCount, 1)
        XCTAssertEqual(currentPageSetupCount, 0)
        XCTAssertEqual(settingsPresenter.showCount, 1)
        XCTAssertFalse(gate.isRecoveryPending)
    }

    func testContinueShowsCurrentPageSetupWhenOnboardingIsComplete() {
        let gate = StartupPresentationGate(recoveryRequired: true)
        let recoveryPresenter = StartupRecoveryWindowPresenterSpy()
        var onboardingCount = 0
        var currentPageSetupCount = 0
        let coordinator = StartupRecoveryCoordinator(
            recoveryRequired: true,
            gate: gate,
            recoveryPresenter: recoveryPresenter,
            showOnboardingIfNeeded: {
                onboardingCount += 1
                return false
            },
            showCurrentPageSetup: { currentPageSetupCount += 1 }
        )
        coordinator.applicationDidFinishLaunching()

        coordinator.continueWithoutSaving()
        coordinator.continueWithoutSaving()

        XCTAssertEqual(recoveryPresenter.hideCount, 1)
        XCTAssertEqual(onboardingCount, 1)
        XCTAssertEqual(currentPageSetupCount, 1)
    }

    func testNormalStartupFollowsOnboardingPathWithoutShowingRecovery() {
        let gate = StartupPresentationGate(recoveryRequired: false)
        let recoveryPresenter = StartupRecoveryWindowPresenterSpy()
        var onboardingCount = 0
        let coordinator = StartupRecoveryCoordinator(
            recoveryRequired: false,
            gate: gate,
            recoveryPresenter: recoveryPresenter,
            showOnboardingIfNeeded: {
                onboardingCount += 1
                return true
            },
            showCurrentPageSetup: {
                XCTFail("Normal startup should leave current-page coordination to the runtime")
            }
        )

        coordinator.applicationDidFinishLaunching()

        XCTAssertEqual(recoveryPresenter.showCount, 0)
        XCTAssertEqual(onboardingCount, 1)
        XCTAssertTrue(gate.allowsCompetingPresentation)
    }

    func testRecoveryPresentationSuppressesOnboardingAndSettings() {
        let gate = StartupPresentationGate(recoveryRequired: true)
        let recoveryPresenter = StartupRecoveryWindowPresenterSpy()
        let settingsPresenter = StartupRecoverySettingsPresenterSpy()
        let guardedSettings = RecoveryGuardedSettingsWindowPresenter(
            presenter: settingsPresenter,
            gate: gate
        )
        var onboardingCount = 0
        var currentPageSetupCount = 0
        let coordinator = StartupRecoveryCoordinator(
            recoveryRequired: true,
            gate: gate,
            recoveryPresenter: recoveryPresenter,
            showOnboardingIfNeeded: {
                onboardingCount += 1
                return true
            },
            showCurrentPageSetup: { currentPageSetupCount += 1 }
        )

        coordinator.applicationDidFinishLaunching()
        guardedSettings.show()

        XCTAssertEqual(recoveryPresenter.showCount, 1)
        XCTAssertEqual(onboardingCount, 0)
        XCTAssertEqual(settingsPresenter.showCount, 0)
        XCTAssertEqual(currentPageSetupCount, 0)
    }
}

@MainActor
private final class StartupRecoveryWindowPresenterSpy: AppWindowPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0

    func show() { showCount += 1 }
    func hide() { hideCount += 1 }
}

@MainActor
private final class StartupRecoverySettingsPresenterSpy: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() { showCount += 1 }
}
