import Carbon.HIToolbox
import Foundation

struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let defaultQuickCapture = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    private static let supportedModifierFlags = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    var isValid: Bool {
        keyCode <= 127 && modifiers != 0 && modifiers & ~Self.supportedModifierFlags == 0
    }

    var displayString: String {
        let modifierSymbols = [
            (UInt32(controlKey), "⌃"),
            (UInt32(optionKey), "⌥"),
            (UInt32(shiftKey), "⇧"),
            (UInt32(cmdKey), "⌘"),
        ]
        return modifierSymbols
            .filter { modifiers & $0.0 != 0 }
            .map(\.1)
            .joined() + keyLabel
    }

    private var keyLabel: String {
        let labels: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        ]
        return labels[keyCode] ?? "Key \(keyCode)"
    }
}

final class GlobalShortcutStore {
    static let key = "globalShortcut"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GlobalShortcut {
        guard let data = defaults.data(forKey: Self.key),
              let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data),
              shortcut.isValid
        else {
            return .default
        }
        return shortcut
    }

    func save(_ shortcut: GlobalShortcut) {
        guard shortcut.isValid, let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

final class QuickCaptureShortcutStore {
    static let key = "quickCaptureShortcut"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> GlobalShortcut {
        guard let data = defaults.data(forKey: Self.key),
              let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data),
              shortcut.isValid
        else { return .defaultQuickCapture }
        return shortcut
    }

    func save(_ shortcut: GlobalShortcut) {
        guard shortcut.isValid, let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

final class TrustedCapturePreferenceStore {
    static let prefillKey = "quickCapturePrefillsClipboard"
    static let insertAtCursorKey = "quickCaptureInsertsAtNotionCursor"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var prefillsClipboard: Bool { defaults.bool(forKey: Self.prefillKey) }
    var insertsAtNotionCursor: Bool { defaults.bool(forKey: Self.insertAtCursorKey) }
    func setPrefillsClipboard(_ value: Bool) { defaults.set(value, forKey: Self.prefillKey) }
    func setInsertsAtNotionCursor(_ value: Bool) { defaults.set(value, forKey: Self.insertAtCursorKey) }
}
