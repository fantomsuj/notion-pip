import Carbon.HIToolbox
import Foundation
import XCTest
@testable import Perch

@MainActor
final class GlobalShortcutTests: XCTestCase {
    func testDefaultShortcutIsCommandShiftPAndValid() {
        XCTAssertEqual(GlobalShortcut.default, GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        ))
        XCTAssertTrue(GlobalShortcut.default.isValid)
    }

    func testShortcutRejectsEmptyAndUnsupportedModifierCombinations() {
        XCTAssertFalse(GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: 0).isValid)
        XCTAssertFalse(GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: 1 << 31).isValid)
    }

    func testPersistedShortcutFallsBackToDefaultWhenStoredValueIsInvalid() throws {
        let defaults = try makeDefaults()
        let store = GlobalShortcutStore(defaults: defaults)
        defaults.set(
            try JSONEncoder().encode(GlobalShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: 0)),
            forKey: GlobalShortcutStore.key
        )

        XCTAssertEqual(store.load(), .default)
    }

    func testHoldToPeekDefaultsOnAndPersistsOptOut() throws {
        let defaults = try makeDefaults()
        let store = HoldToPeekPreferenceStore(defaults: defaults)

        XCTAssertTrue(store.load())

        store.save(false)

        XCTAssertFalse(store.load())
    }

    func testLegacyQuickCapturePreferenceRemovalDeletesOnlyRetiredKeys() throws {
        let defaults = try makeDefaults()
        defaults.set(Data([0x01]), forKey: "quickCaptureShortcut")
        defaults.set(true, forKey: "quickCapturePrefillsClipboard")
        defaults.set(true, forKey: "quickCaptureInsertsAtNotionCursor")
        defaults.set("preserved", forKey: "unrelatedPreference")

        _ = GlobalShortcutStore(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "quickCaptureShortcut"))
        XCTAssertNil(defaults.object(forKey: "quickCapturePrefillsClipboard"))
        XCTAssertNil(defaults.object(forKey: "quickCaptureInsertsAtNotionCursor"))
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "preserved")
    }

    func testApplyingShortcutPersistsAndRegistersTheNewValueImmediately() throws {
        let defaults = try makeDefaults()
        let registrar = ShortcutRegistrarSpy()
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))
        let runtime = makeRuntime(registrar: registrar, defaults: defaults)
        runtime.start()

        XCTAssertTrue(runtime.applyGlobalShortcut(shortcut))

        XCTAssertEqual(runtime.globalShortcut, shortcut)
        XCTAssertEqual(registrar.registeredShortcuts, [.default, shortcut])
        XCTAssertEqual(GlobalShortcutStore(defaults: defaults).load(), shortcut)
    }

    func testFailedShortcutReplacementKeepsThePriorShortcutAndReportsHealth() throws {
        let defaults = try makeDefaults()
        let registrar = ShortcutRegistrarSpy(failures: [GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))])
        let runtime = makeRuntime(registrar: registrar, defaults: defaults)
        runtime.start()
        let requested = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))

        XCTAssertFalse(runtime.applyGlobalShortcut(requested))

        XCTAssertEqual(runtime.globalShortcut, .default)
        XCTAssertEqual(GlobalShortcutStore(defaults: defaults).load(), .default)
        XCTAssertTrue(runtime.serviceHealth.issues.contains(.globalShortcutUnavailable))
    }

    func testResetGlobalShortcutRestoresCommandShiftP() throws {
        let defaults = try makeDefaults()
        let registrar = ShortcutRegistrarSpy()
        let runtime = makeRuntime(registrar: registrar, defaults: defaults)
        runtime.start()
        XCTAssertTrue(runtime.applyGlobalShortcut(GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))))

        runtime.resetGlobalShortcut()

        XCTAssertEqual(runtime.globalShortcut, .default)
        XCTAssertEqual(registrar.registeredShortcuts.last, .default)
    }

    func testRegistrarRestoresTheKnownGoodShortcutWhenReplacementFails() throws {
        let engine = ShortcutRegistrationEngineSpy()
        let registrar = CarbonGlobalShortcutRegistrar(engine: engine)
        let replacement = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))

        try registrar.register(shortcut: .default, handler: {})
        engine.failingShortcuts = [replacement]

        XCTAssertThrowsError(try registrar.register(shortcut: replacement, handler: {}))
        XCTAssertEqual(engine.installedShortcuts, [.default, replacement, .default])
        XCTAssertEqual(engine.uninstallCount, 1)
    }

    func testRevalidationReinstallsAnUnchangedShortcut() throws {
        let engine = ShortcutRegistrationEngineSpy()
        let registrar = CarbonGlobalShortcutRegistrar(engine: engine)

        try registrar.register(shortcut: .default, handler: {})
        try registrar.revalidate()

        XCTAssertEqual(engine.installedShortcuts, [.default, .default])
        XCTAssertEqual(engine.uninstallCount, 1)
    }

    func testRevalidationWithoutARegisteredShortcutDoesNothing() throws {
        let engine = ShortcutRegistrationEngineSpy()
        let registrar = CarbonGlobalShortcutRegistrar(engine: engine)

        try registrar.revalidate()

        XCTAssertEqual(engine.installedShortcuts, [])
        XCTAssertEqual(engine.uninstallCount, 0)
    }

    func testRegistrarClassifiesExistingCarbonHotKeyAsConflict() {
        let engine = ShortcutRegistrationEngineSpy()
        engine.installError = GlobalShortcutRegistrationError.hotKey(
            OSStatus(eventHotKeyExistsErr)
        )
        let registrar = CarbonGlobalShortcutRegistrar(engine: engine)

        XCTAssertThrowsError(try registrar.register(shortcut: .default, handler: {})) { error in
            XCTAssertEqual(error as? GlobalShortcutRegistrationFailure, .conflict)
        }
    }

    func testRegistrarClassifiesOtherCarbonFailureAsTransient() {
        let engine = ShortcutRegistrationEngineSpy()
        engine.installError = GlobalShortcutRegistrationError.eventHandler(
            OSStatus(eventInternalErr)
        )
        let registrar = CarbonGlobalShortcutRegistrar(engine: engine)

        XCTAssertThrowsError(try registrar.register(shortcut: .default, handler: {})) { error in
            XCTAssertEqual(error as? GlobalShortcutRegistrationFailure, .transient)
        }
    }

    func testFailedRevalidationAndRollbackAllowsARealRegistrationRetry() throws {
        let engine = ShortcutRegistrationEngineSpy()
        let registrar = CarbonGlobalShortcutRegistrar(engine: engine)
        try registrar.register(shortcut: .default, handler: {})
        engine.installError = GlobalShortcutRegistrationError.hotKey(
            OSStatus(eventHotKeyExistsErr)
        )
        engine.failuresRemaining = 2

        XCTAssertThrowsError(try registrar.revalidate())
        engine.installError = nil
        try registrar.register(shortcut: .default, handler: {})

        XCTAssertEqual(
            engine.installedShortcuts,
            [.default, .default, .default, .default]
        )
    }

    func testCarbonHotKeyEnginesOnlyAcceptTheirOwnEventIdentity() {
        let panelEngine = CarbonEventHotKeyEngine()
        let alternateEngine = CarbonEventHotKeyEngine()

        XCTAssertNotEqual(panelEngine.registrationID.id, alternateEngine.registrationID.id)
        XCTAssertTrue(panelEngine.accepts(eventHotKeyID: panelEngine.registrationID))
        XCTAssertFalse(panelEngine.accepts(eventHotKeyID: alternateEngine.registrationID))
        XCTAssertTrue(alternateEngine.accepts(eventHotKeyID: alternateEngine.registrationID))
        XCTAssertFalse(alternateEngine.accepts(eventHotKeyID: panelEngine.registrationID))
    }

    private func makeRuntime(registrar: ShortcutRegistrarSpy, defaults: UserDefaults) -> AppRuntime {
        AppRuntime(
            panelCoordinator: ShortcutTestPanelCoordinator(),
            shortcutRegistrar: registrar,
            shortcutStore: GlobalShortcutStore(defaults: defaults)
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GlobalShortcutTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw XCTSkip("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

@MainActor
private final class ShortcutRegistrarSpy: GlobalShortcutRegistering {
    private let failures: Set<GlobalShortcut>
    private(set) var registeredShortcuts: [GlobalShortcut] = []

    init(failures: Set<GlobalShortcut> = []) {
        self.failures = failures
    }

    func register(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        if failures.contains(shortcut) {
            throw ShortcutRegistrarSpyError.registrationFailed
        }
        registeredShortcuts.append(shortcut)
    }

    func revalidate() throws {}
    func unregister() {}
}

private enum ShortcutRegistrarSpyError: Error {
    case registrationFailed
}

@MainActor
private final class ShortcutRegistrationEngineSpy: GlobalShortcutRegistrationEngine {
    var failingShortcuts: Set<GlobalShortcut> = []
    var installError: Error?
    var failuresRemaining = 0
    private(set) var installedShortcuts: [GlobalShortcut] = []
    private(set) var uninstallCount = 0

    func install(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        installedShortcuts.append(shortcut)
        if let installError, failuresRemaining != 0 {
            failuresRemaining -= 1
            throw installError
        }
        if let installError, failuresRemaining == 0 {
            throw installError
        }
        if failingShortcuts.contains(shortcut) {
            throw ShortcutRegistrarSpyError.registrationFailed
        }
    }

    func uninstall() {
        uninstallCount += 1
    }
}

@MainActor
private final class ShortcutTestPanelCoordinator: PiPPanelCoordinating {
    var onPresentationStateChange: (@MainActor () -> Void)?
    var currentPage: NotionPageReference?
    var isVisible = false
    var presentationState: PiPPresentationState { .unavailable }
    func show(page: NotionPageReference) {}
    func reloadPinnedPage(_ page: NotionPageReference) {}
    func replace(page: NotionPageReference) {}
    func showCurrentPage() -> Bool { false }
    func stashOrRestoreCurrentPage() -> Bool { false }
}
