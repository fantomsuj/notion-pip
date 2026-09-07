import Carbon.HIToolbox
import Foundation

struct FlipShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Command-Shift-F. Distinct from Perch's Command-Shift-P.
    static let `default` = FlipShortcut(
        keyCode: UInt32(kVK_ANSI_F),
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

    var tutorialDisplayString: String {
        let modifierLabels = [
            (UInt32(cmdKey), "Cmd"),
            (UInt32(shiftKey), "Shift"),
            (UInt32(controlKey), "Control"),
            (UInt32(optionKey), "Option"),
        ]
        let labels = modifierLabels
            .filter { modifiers & $0.0 != 0 }
            .map(\.1)
            + [keyLabel]
        return labels.joined(separator: " + ")
    }

    private var keyLabel: String {
        keyCode == UInt32(kVK_ANSI_F) ? "F" : "Key \(keyCode)"
    }
}

final class FlipShortcutStore {
    static let key = "flipShortcut"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FlipShortcut {
        guard let data = defaults.data(forKey: Self.key),
              let shortcut = try? JSONDecoder().decode(FlipShortcut.self, from: data),
              shortcut.isValid
        else {
            return .default
        }
        return shortcut
    }

    func save(_ shortcut: FlipShortcut) {
        guard shortcut.isValid, let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
