import Foundation

@MainActor
protocol AgentStreamingPreferenceStoring: AnyObject {
    func load() -> Bool
    func save(_ enabled: Bool)
}

@MainActor
final class AgentStreamingPreferenceStore: AgentStreamingPreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "localAgentStreamingEnabled"
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
