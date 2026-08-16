import Foundation

@MainActor
protocol ContextSuggestionPreferenceStoring: AnyObject {
    func load() -> Bool
    func save(_ enabled: Bool)
}

@MainActor
final class ContextSuggestionPreferenceStore: ContextSuggestionPreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "contextSuggestionsEnabled"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> Bool {
        defaults.bool(forKey: key)
    }

    func save(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }
}
