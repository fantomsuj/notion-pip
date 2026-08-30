import Foundation

struct StashHandleVisibilityPreferenceStore {
    static let key = "hideStashHandle"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        guard defaults.object(forKey: Self.key) != nil else { return false }
        return defaults.bool(forKey: Self.key)
    }

    func save(_ isHidden: Bool) {
        defaults.set(isHidden, forKey: Self.key)
    }
}
