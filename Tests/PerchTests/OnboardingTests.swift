import AppKit
import XCTest
@testable import Perch

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

final class OnboardingContentTests: XCTestCase {
    func testPanelControlsStepExplainsDiscoveryAndTitleBarMaximizeGesture() {
        XCTAssertEqual(OnboardingStep.allCases.count, 5)
        XCTAssertEqual(OnboardingStep.panelControls.sidebarTitle, "Panel controls")
        XCTAssertTrue(OnboardingStep.panelControls.detail.contains("top edge"))
        XCTAssertTrue(OnboardingStep.panelControls.detail.contains("corner arrows"))
        XCTAssertTrue(OnboardingStep.panelControls.detail.contains("centered toolbar"))
        XCTAssertFalse(OnboardingStep.panelControls.detail.contains("stay visible"))
        XCTAssertTrue(OnboardingStep.panelControls.detail.contains("Double-click"))
        XCTAssertTrue(OnboardingStep.panelControls.detail.contains("maximize"))
    }

    func testPanelControlsStepCoversEveryHoverRevealedToolbarAction() {
        XCTAssertEqual(
            OnboardingToolbarControl.all.map(\.title),
            [
                "New Notion page",
                "Switch page",
                "Reload current page",
                "Open in browser",
                "App menu & sizes",
                "Stash to edge",
            ]
        )
    }

    func testPanelControlsStepUsesEveryCornerArrow() {
        XCTAssertEqual(
            PanelCorner.allCases.map(\.symbolName),
            [
                "arrow.up.left",
                "arrow.up.right",
                "arrow.down.left",
                "arrow.down.right",
            ]
        )
    }
}

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    func testStartupWaitsUntilApplicationFinishesLaunchingToPresentOnboarding() {
        let panel = RuntimePanelCoordinator()
        let runtime = makeRuntime(panel: panel)
        let appDelegate = AppDelegate()
        var presentationCount = 0

        AppStartup.start(
            runtime: runtime,
            appDelegate: appDelegate,
            applicationDidFinishLaunching: { presentationCount += 1 }
        )

        XCTAssertEqual(presentationCount, 0)

        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(presentationCount, 1)
    }

    func testFirstLaunchPresentsOnboardingUntilItIsCompleted() throws {
        let harness = try makeHarness()

        harness.coordinator.showIfNeeded()

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertTrue(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))

        harness.complete?()

        XCTAssertEqual(harness.presenter.hideCount, 1)
        XCTAssertEqual(harness.finish.finishCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))

        harness.coordinator.showIfNeeded()
        XCTAssertEqual(harness.presenter.showCount, 1)
    }

    func testCompletingDoesNotOpenAnotherSetupSurface() throws {
        let harness = try makeHarness()
        harness.coordinator.showIfNeeded()

        harness.complete?()

        XCTAssertEqual(harness.presenter.hideCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    func testOpeningSettingsCompletesOnboardingAndHandsOffToSettings() throws {
        let harness = try makeHarness()
        harness.coordinator.showIfNeeded()

        harness.openSettings?()

        XCTAssertEqual(harness.presenter.hideCount, 1)
        XCTAssertEqual(harness.settings.showCount, 1)
        XCTAssertEqual(harness.finish.finishCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    func testSuccessfulPageOpeningCompletesAndClosesOnboarding() throws {
        let harness = try makeHarness(pageOpeningSucceeds: true)
        harness.coordinator.showIfNeeded()

        harness.openPage?()

        XCTAssertEqual(harness.presenter.hideCount, 1)
        XCTAssertEqual(harness.finish.finishCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    func testFailedPageOpeningLeavesOnboardingOpen() throws {
        let harness = try makeHarness(pageOpeningSucceeds: false)
        harness.coordinator.showIfNeeded()

        harness.openPage?()

        XCTAssertEqual(harness.presenter.hideCount, 0)
        XCTAssertEqual(harness.finish.finishCount, 0)
        XCTAssertTrue(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    func testReplayAlwaysPresentsWithoutResettingCompletion() throws {
        let harness = try makeHarness(completedVersion: OnboardingCoordinator.currentVersion)

        harness.coordinator.show()

        XCTAssertEqual(harness.presenter.showCount, 1)
        XCTAssertFalse(harness.store.shouldPresent(version: OnboardingCoordinator.currentVersion))
    }

    private func makeHarness(
        completedVersion: Int? = nil,
        pageOpeningSucceeds: Bool = false
    ) throws -> OnboardingHarness {
        let defaultsName = "OnboardingCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        let store = OnboardingPreferenceStore(defaults: defaults)
        if let completedVersion {
            store.markCompleted(version: completedVersion)
        }
        let presenter = OnboardingWindowPresenterSpy()
        let settings = OnboardingSettingsPresenterSpy()
        let finish = OnboardingFinishSpy()
        var openPage: (() -> Void)?
        var complete: (() -> Void)?
        var openSettings: (() -> Void)?
        let coordinator = OnboardingCoordinator(
            preferenceStore: store,
            settingsWindowPresenter: settings,
            openCurrentPage: { pageOpeningSucceeds },
            onFinish: finish.perform,
            makeWindowPresenter: { pageAction, completion, settingsAction in
                openPage = pageAction
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
            finish: finish,
            openPage: { openPage?() },
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
    let finish: OnboardingFinishSpy
    let openPage: (() -> Void)?
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

@MainActor
private final class OnboardingFinishSpy {
    private(set) var finishCount = 0

    func perform() { finishCount += 1 }
}
