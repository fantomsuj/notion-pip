import Foundation

/// Remembers whether the panel was tucked away at the screen edge, so the next
/// launch (including Launch at Login) can come back stashed instead of showing
/// the panel and loading Notion.
struct PanelStashStateStore {
    static let key = "panelWasStashed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    func save(_ isStashed: Bool) {
        guard load() != isStashed else { return }
        defaults.set(isStashed, forKey: Self.key)
    }
}
