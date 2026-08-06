import XCTest
@testable import NotionPiP

final class OnboardingPreferenceStoreTests: XCTestCase {
    func testCompletionIsVersionedSoNewOnboardingCanAppearAfterAnUpgrade() throws {
        let defaultsName = "OnboardingPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        let store = OnboardingPreferenceStore(defaults: defaults)

        XCTAssertTrue(store.shouldPresent(version: 1))

        store.markCompleted(version: 1)

        XCTAssertFalse(store.shouldPresent(version: 1))
        XCTAssertTrue(store.shouldPresent(version: 2))
    }
}

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    func testFirstLaunchPresentsOnboardingUntilItIsCompleted() throws {
        let harness = try makeHarness()

        harness.coordinator.showIfNeeded()

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertTrue(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))

        harness.complete?()

        XCTAssertEqual(harness.presenter.hideCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))

        harness.coordinator.showIfNeeded()
        XCTAssertEqual(harness.presenter.showCount, 1)
    }

    func testOpeningSettingsCompletesOnboardingAndHandsOffToSettings() throws {
        let harness = try makeHarness()
        harness.coordinator.showIfNeeded()

        harness.openSettings?()

        XCTAssertEqual(harness.presenter.hideCount, 1)
        XCTAssertEqual(harness.settings.showCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    func testReplayAlwaysPresentsWithoutResettingCompletion() throws {
        let harness = try makeHarness(completedVersion: OnboardingCoordinator.currentVersion)

        harness.coordinator.show()

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    private func makeHarness(completedVersion: Int? = nil) throws -> OnboardingHarness {
        let defaultsName = "OnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        let store = OnboardingPreferenceStore(defaults: defaults)
        if let completedVersion {
            store.markCompleted(version: completedVersion)
        }
        let presenter = OnboardingWindowPresenterSpy()
        let settings = OnboardingSettingsPresenterSpy()
        var complete: (() -> Void)?
        var openSettings: (() -> Void)?
        let coordinator = OnboardingCoordinator(
            preferenceStore: store,
            settingsWindowPresenter: settings,
            makeWindowPresenter: { completion, settingsAction in
                complete = completion
                openSettings = settingsAction
                return presenter
            }
        )
        return OnboardingHarness(
            coordinator: coordinator,
            store: store,
            presenter: presenter,
            settings: settings,
            complete: { complete?() },
            openSettings: { openSettings?() }
        )
    }
}

@MainActor
private struct OnboardingHarness {
    let coordinator: OnboardingCoordinator
    let store: OnboardingPreferenceStore
    let presenter: OnboardingWindowPresenterSpy
    let settings: OnboardingSettingsPresenterSpy
    let complete: (() -> Void)?
    let openSettings: (() -> Void)?
}

@MainActor
private final class OnboardingWindowPresenterSpy: AppWindowPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0

    func show() { showCount += 1 }
    func hide() { hideCount += 1 }
}

@MainActor
private final class OnboardingSettingsPresenterSpy: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() { showCount += 1 }
}
