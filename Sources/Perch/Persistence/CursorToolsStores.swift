import Foundation

/// Whether the cursor tools (carry a screenshot, jot a margin note) are on.
/// Off until the person turns them on in Settings.
struct CursorToolsPreferenceStore {
    static let key = "cursorToolsEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    func save(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.key)
    }
}

/// Margin notes that could not land in Notion yet, oldest first. They stay on
/// this Mac until they are dropped into a page, copied, or cleared.
struct MarginNoteQueueStore {
    static let key = "marginNoteQueue"
    static let maximumCount = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [MarginNote] {
        guard let data = defaults.data(forKey: Self.key),
              let notes = try? JSONDecoder().decode([MarginNote].self, from: data)
        else {
            return []
        }
        return notes
    }

    func save(_ notes: [MarginNote]) {
        let kept = Array(notes.suffix(Self.maximumCount))
        guard !kept.isEmpty else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(kept) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
