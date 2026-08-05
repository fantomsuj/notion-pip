import Carbon.HIToolbox
import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class GlobalShortcutTests: XCTestCase {
    func testDefaultShortcutIsCommandShiftPAndValid() {
        XCTAssertEqual(GlobalShortcut.default, GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        ))
        XCTAssertTrue(GlobalShortcut.default.isValid)
        XCTAssertEqual(GlobalShortcut.defaultQuickCapture, GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey)
        ))
    }

    func testQuickCaptureShortcutUsesIndependentPersistenceKey() throws {
        let defaults = try makeDefaults()
        let panelStore = GlobalShortcutStore(defaults: defaults)
        let captureStore = QuickCaptureShortcutStore(defaults: defaults)
        let capture = GlobalShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | optionKey))

        captureStore.save(capture)

        XCTAssertEqual(captureStore.load(), capture)
        XCTAssertEqual(panelStore.load(), .default)
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

    func testCarbonHotKeyEnginesOnlyAcceptTheirOwnEventIdentity() {
        let panelEngine = CarbonEventHotKeyEngine()
        let captureEngine = CarbonEventHotKeyEngine()

        XCTAssertNotEqual(panelEngine.registrationID.id, captureEngine.registrationID.id)
        XCTAssertTrue(panelEngine.accepts(eventHotKeyID: panelEngine.registrationID))
        XCTAssertFalse(panelEngine.accepts(eventHotKeyID: captureEngine.registrationID))
        XCTAssertTrue(captureEngine.accepts(eventHotKeyID: captureEngine.registrationID))
        XCTAssertFalse(captureEngine.accepts(eventHotKeyID: panelEngine.registrationID))
    }

    private func makeRuntime(registrar: ShortcutRegistrarSpy, defaults: UserDefaults) -> AppRuntime {
        AppRuntime(
            panelCoordinator: ShortcutTestPanelCoordinator(),
            shortcutRegistrar: registrar,
            shortcutStore: GlobalShortcutStore(defaults: defaults),
            credentialVault: PersonalTokenCredentialVault(store: ShortcutTestSecretStore())
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

    func unregister() {}
}

private enum ShortcutRegistrarSpyError: Error {
    case registrationFailed
}

@MainActor
private final class ShortcutRegistrationEngineSpy: GlobalShortcutRegistrationEngine {
    var failingShortcuts: Set<GlobalShortcut> = []
    private(set) var installedShortcuts: [GlobalShortcut] = []
    private(set) var uninstallCount = 0

    func install(shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        installedShortcuts.append(shortcut)
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
    var currentPage: NotionPageReference?
    var isVisible = false
    var presentationState: PiPPresentationState { .unavailable }
    func show(page: NotionPageReference) {}
    func reloadPinnedPage(_ page: NotionPageReference) {}
    func replace(page: NotionPageReference) {}
    func showCurrentPage() -> Bool { false }
    func stashOrRestoreCurrentPage() -> Bool { false }
}

private final class ShortcutTestSecretStore: SecretStoring {
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws {}
    func delete() throws {}
}
