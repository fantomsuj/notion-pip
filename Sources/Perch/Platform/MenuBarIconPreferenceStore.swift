import Foundation

struct MenuBarIconPreferenceStore {
    static let key = "showMenuBarIcon"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        guard defaults.object(forKey: Self.key) != nil else { return true }
        return defaults.bool(forKey: Self.key)
    }

    func save(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: Self.key)
    }
}
