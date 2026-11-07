import AppKit
import Carbon.HIToolbox
import Combine
import OSLog

/// The two cursor tools and their shortcuts:
///
/// - Carry a screenshot (Control-Option-Command-S): pick an area, then it
///   rides the pointer. Double-click to drop it, shake to toss it.
/// - Jot a margin note (Control-Option-Command-N): type a note at the pointer
///   in any app. It lands in the Perch page with its time and source.
///
/// Both are off until turned on in Settings.
@MainActor
final class CursorToolsController: ObservableObject {
    static let carryShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )
    static let noteShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isAccessibilityTrusted: Bool
    @Published private(set) var shortcutProblem: String?
    @Published private(set) var isCarrying = false

    let notes: MarginNoteController
    private let carry: CursorCarryController
    private let preferenceStore: CursorToolsPreferenceStore
    private let carryRegistrar: any GlobalShortcutRegistering
    private let noteRegistrar: any GlobalShortcutRegistering
    private let logger = Logger(subsystem: "com.fantomsuj.Perch", category: "cursor-tools")
    private var notesCancellable: AnyCancellable?

    init(
        target: (any AgentStreamTarget)?,
        preferenceStore: CursorToolsPreferenceStore = CursorToolsPreferenceStore(),
        carryRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
        noteRegistrar: any GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar()
    ) {
        let toast = CursorToast()
        self.preferenceStore = preferenceStore
        self.carryRegistrar = carryRegistrar
        self.noteRegistrar = noteRegistrar
        carry = CursorCarryController(toast: toast)
        notes = MarginNoteController(target: target, notify: { toast.show($0) })
        isEnabled = preferenceStore.load()
        isAccessibilityTrusted = CursorToolsAccessibility.isTrusted
        carry.onPhaseChange = { [weak self] phase in
            self?.isCarrying = phase == .carrying
        }
        // Settings shows the waiting-note count, so pass the notes' changes on.
        notesCancellable = notes.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func startIfPreferred() {
        guard isEnabled else { return }
        registerShortcuts()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        preferenceStore.save(enabled)
        if enabled {
            registerShortcuts()
            if !CursorToolsAccessibility.isTrusted {
                CursorToolsAccessibility.requestTrust()
            }
        } else {
            unregisterShortcuts()
            carry.stop()
            notes.stop()
        }
        refreshPermissions()
    }

    func carryScreenshot() {
        carry.beginCarry()
    }

    func tossCarriedScreenshot() {
        carry.toss()
    }

    func jotNote() {
        notes.beginNote()
    }

    func refreshPermissions() {
        isAccessibilityTrusted = CursorToolsAccessibility.isTrusted
    }

    func requestAccessibility() {
        if !CursorToolsAccessibility.requestTrust() {
            CursorToolsAccessibility.openSettings()
        }
        refreshPermissions()
    }

    func prepareForTermination() {
        unregisterShortcuts()
        carry.stop()
        notes.stop()
    }

    private func registerShortcuts() {
        var failed: [String] = []
        do {
            try carryRegistrar.register(shortcut: Self.carryShortcut) { [weak self] in
                self?.carryScreenshot()
            }
        } catch {
            logger.error("Carry-screenshot shortcut unavailable")
            failed.append(Self.carryShortcut.displayString)
        }
        do {
            try noteRegistrar.register(shortcut: Self.noteShortcut) { [weak self] in
                self?.jotNote()
            }
        } catch {
            logger.error("Margin-note shortcut unavailable")
            failed.append(Self.noteShortcut.displayString)
        }
        shortcutProblem = failed.isEmpty
            ? nil
            : "Another app is using \(failed.joined(separator: " and ")). Quit it or change its shortcut, then turn cursor tools off and on."
    }

    private func unregisterShortcuts() {
        carryRegistrar.unregister()
        noteRegistrar.unregister()
        shortcutProblem = nil
    }
}
