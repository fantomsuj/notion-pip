import Foundation

protocol PanelSizePreferencesPersisting {
    func load() -> PanelSizePreferences?
    func save(_ preferences: PanelSizePreferences) throws
}

final class PanelSizePreferencesStore: PanelSizePreferencesPersisting {
    static let key = "panelSizePreferences"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
    }

    /// Returns `nil` when preferences have never been saved, allowing legacy
    /// AppKit frame restoration to remain authoritative for existing users.
    /// Invalid saved data falls back to fresh, safe preferences.
    func load() -> PanelSizePreferences? {
        guard defaults.object(forKey: Self.key) != nil else {
            return nil
        }
        guard let data = defaults.data(forKey: Self.key),
            let preferences = try? decoder.decode(
                PanelSizePreferences.self,
                from: data
            )
        else {
            return .default
        }
        return preferences
    }

    func save(_ preferences: PanelSizePreferences) throws {
        defaults.set(try encoder.encode(preferences), forKey: Self.key)
    }
}
