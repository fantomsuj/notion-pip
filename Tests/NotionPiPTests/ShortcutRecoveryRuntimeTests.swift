import Carbon.HIToolbox
import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class ShortcutRecoveryRuntimeTests: XCTestCase {
    func testLifecycleRecoveryRevalidatesBothShortcutsAndClearsHealth() throws {
        let harness = try makeHarness(
            initialHealth: ServiceHealthState(issues: [
                .globalShortcutUnavailable,
                .quickCaptureShortcutUnavailable,
            ])
        )
        harness.runtime.start()
        harness.runtime.reportServiceIssue(.globalShortcutUnavailable)
        harness.runtime.reportServiceIssue(.quickCaptureShortcutUnavailable)

        harness.postLifecycleEvent()
        harness.scheduler.runNextActive()

        XCTAssertEqual(harness.panelRegistrar.revalidationCount, 1)
        XCTAssertEqual(harness.captureRegistrar.revalidationCount, 1)
        XCTAssertTrue(harness.runtime.serviceHealth.isHealthy)
    }

    func testPersistentConflictReportsHealthWithoutRetrying() throws {
        let harness = try makeHarness()
        harness.panelRegistrar.revalidationResults = [.failure(.conflict)]
        harness.runtime.start()

        harness.postLifecycleEvent()
        harness.scheduler.runNextActive()

        XCTAssertEqual(harness.panelRegistrar.revalidationCount, 1)
        XCTAssertTrue(
            harness.runtime.serviceHealth.issues.contains(.globalShortcutUnavailable)
        )
        XCTAssertEqual(harness.scheduler.activeCount, 0)
    }

    func testTransientFailureRetriesOnceAndClearsHealthAfterSuccess() throws {
        let harness = try makeHarness()
        harness.panelRegistrar.revalidationResults = [
            .failure(.transient),
            .success(()),
        ]
        harness.runtime.start()

        harness.postLifecycleEvent()
        harness.scheduler.runNextActive()
        XCTAssertEqual(harness.scheduler.activeCount, 1)

        harness.scheduler.runNextActive()

        XCTAssertEqual(harness.panelRegistrar.revalidationCount, 2)
        XCTAssertFalse(
            harness.runtime.serviceHealth.issues.contains(.globalShortcutUnavailable)
        )
        XCTAssertEqual(harness.scheduler.activeCount, 0)
    }

    func testQuickCaptureOnlyFailureDoesNotForceMenuBarFallback() throws {
        let harness = try makeHarness(savedMenuBarVisibility: false)
        harness.captureRegistrar.revalidationResults = [.failure(.conflict)]
        harness.runtime.start()

        harness.postLifecycleEvent()
        harness.scheduler.runNextActive()

        XCTAssertFalse(
            harness.runtime.serviceHealth.issues.contains(.globalShortcutUnavailable)
        )
        XCTAssertTrue(
            harness.runtime.serviceHealth.issues.contains(.quickCaptureShortcutUnavailable)
        )
        XCTAssertFalse(harness.runtime.effectiveMenuBarIconVisibility)
        XCTAssertFalse(harness.runtime.isMenuBarIconVisibilityForced)
    }

    func testSettingsChangeInvalidatesPendingLifecycleRecovery() throws {
        let harness = try makeHarness()
        harness.runtime.start()
        harness.postLifecycleEvent()
        let staleRecovery = try XCTUnwrap(harness.scheduler.last)
        let replacement = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey | optionKey)
        )

        XCTAssertTrue(harness.runtime.applyGlobalShortcut(replacement))
        staleRecovery.runEvenIfCancelled()

        XCTAssertEqual(harness.runtime.globalShortcut, replacement)
        XCTAssertEqual(harness.panelRegistrar.revalidationCount, 0)
        XCTAssertEqual(harness.captureRegistrar.revalidationCount, 0)
    }

    func testFailedSettingsRegistrationLeavesBothSurfacesAndStoresUnchanged() throws {
        let harness = try makeHarness()
        harness.runtime.start()
        let replacement = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | optionKey)
        )
        harness.captureRegistrar.failingRegistrations.insert(replacement)

        XCTAssertFalse(harness.runtime.applyQuickCaptureShortcut(replacement))

        XCTAssertEqual(harness.runtime.globalShortcut, .default)
        XCTAssertEqual(harness.runtime.quickCaptureShortcut, .defaultQuickCapture)
        XCTAssertEqual(harness.panelStore.load(), .default)
        XCTAssertEqual(harness.captureStore.load(), .defaultQuickCapture)
    }

    func testDuplicateChordIsRejectedWithoutRegistrationOrPersistence() throws {
        let harness = try makeHarness()
        harness.runtime.start()
        let registrationCount = harness.captureRegistrar.registeredShortcuts.count

        XCTAssertFalse(harness.runtime.applyQuickCaptureShortcut(.default))

        XCTAssertEqual(
            harness.captureRegistrar.registeredShortcuts.count,
            registrationCount
        )
        XCTAssertEqual(harness.runtime.globalShortcut, .default)
        XCTAssertEqual(harness.runtime.quickCaptureShortcut, .defaultQuickCapture)
        XCTAssertEqual(harness.captureStore.load(), .defaultQuickCapture)
    }

    func testRuntimeTeardownRemovesLifecycleObservers() throws {
        let harness = try makeHarness()
        weak let weakRuntime = harness.runtime
        harness.runtime.start()

        harness.releaseRuntime()
        harness.postLifecycleEvent()

        XCTAssertNil(weakRuntime)
        XCTAssertEqual(harness.scheduler.activeCount, 0)
    }

    private func makeHarness(
        initialHealth: ServiceHealthState = .healthy,
        savedMenuBarVisibility: Bool = true
    ) throws -> ShortcutRecoveryRuntimeHarness {
        try ShortcutRecoveryRuntimeHarness(
            initialHealth: initialHealth,
            savedMenuBarVisibility: savedMenuBarVisibility
        )
    }
}

@MainActor
private final class ShortcutRecoveryRuntimeHarness {
    let center = NotificationCenter()
    let scheduler = RuntimeRecoverySchedulerSpy()
    let panelRegistrar = LifecycleShortcutRegistrarSpy()
    let captureRegistrar = LifecycleShortcutRegistrarSpy()
    let panelStore: GlobalShortcutStore
    let captureStore: QuickCaptureShortcutStore
    private(set) var runtime: AppRuntime!

    init(
        initialHealth: ServiceHealthState,
        savedMenuBarVisibility: Bool
    ) throws {
        let suiteName = "ShortcutRecoveryRuntimeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        panelStore = GlobalShortcutStore(defaults: defaults)
        captureStore = QuickCaptureShortcutStore(defaults: defaults)
        let menuStore = MenuBarIconPreferenceStore(defaults: defaults)
        menuStore.save(savedMenuBarVisibility)
        runtime = AppRuntime(
            panelCoordinator: RuntimePanelCoordinator(),
            shortcutRegistrar: panelRegistrar,
            shortcutStore: panelStore,
            quickCaptureShortcutRegistrar: captureRegistrar,
            quickCaptureShortcutStore: captureStore,
            menuBarIconPreferenceStore: menuStore,
            credentialVault: PersonalTokenCredentialVault(
                store: ShortcutRecoverySecretStore()
            ),
            initialServiceHealth: initialHealth,
            shortcutLifecycleCoordinatorFactory: { [center, scheduler] onRecovery in
                ShortcutLifecycleCoordinator(
                    notificationCenter: center,
                    notificationNames: [.shortcutRecoveryLifecycleEvent],
                    scheduler: scheduler,
                    onRecovery: onRecovery
                )
            }
        )
    }

    func postLifecycleEvent() {
        center.post(name: .shortcutRecoveryLifecycleEvent, object: nil)
    }

    func releaseRuntime() {
        runtime = nil
    }
}

private extension Notification.Name {
    static let shortcutRecoveryLifecycleEvent = Notification.Name(
        "ShortcutRecoveryRuntimeTests.lifecycleEvent"
    )
}

@MainActor
private final class LifecycleShortcutRegistrarSpy: GlobalShortcutRegistering {
    var failingRegistrations: Set<GlobalShortcut> = []
    var revalidationResults: [Result<Void, GlobalShortcutRegistrationFailure>] = []
    private(set) var registeredShortcuts: [GlobalShortcut] = []
    private(set) var revalidationCount = 0

    func register(
        shortcut: GlobalShortcut,
        handler: @escaping @MainActor () -> Void
    ) throws {
        guard !failingRegistrations.contains(shortcut) else {
            throw GlobalShortcutRegistrationFailure.conflict
        }
        registeredShortcuts.append(shortcut)
    }

    func revalidate() throws {
        revalidationCount += 1
        guard !revalidationResults.isEmpty else { return }
        try revalidationResults.removeFirst().get()
    }

    func unregister() {}
}

@MainActor
private final class RuntimeRecoverySchedulerSpy: ShortcutRecoveryScheduling {
    private(set) var scheduled: [RuntimeScheduledRecovery] = []
    var last: RuntimeScheduledRecovery? { scheduled.last }
    var activeCount: Int { scheduled.count(where: { !$0.isCancelled && !$0.didRun }) }

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor () -> Void
    ) -> any ShortcutRecoveryCancellation {
        let recovery = RuntimeScheduledRecovery(operation: operation)
        scheduled.append(recovery)
        return recovery
    }

    func runNextActive() {
        scheduled.first(where: { !$0.isCancelled && !$0.didRun })?.run()
    }
}

@MainActor
private final class RuntimeScheduledRecovery: ShortcutRecoveryCancellation {
    private let operation: @MainActor () -> Void
    private(set) var isCancelled = false
    private(set) var didRun = false

    init(operation: @escaping @MainActor () -> Void) {
        self.operation = operation
    }

    func cancel() { isCancelled = true }

    func run() {
        guard !isCancelled, !didRun else { return }
        runEvenIfCancelled()
    }

    func runEvenIfCancelled() {
        guard !didRun else { return }
        didRun = true
        operation()
    }
}

private final class ShortcutRecoverySecretStore: SecretStoring {
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws {}
    func delete() throws {}
}
