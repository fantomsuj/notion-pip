import Foundation

struct CustomPinnedURLSnapshot: Equatable, Sendable {
    var isEnabled: Bool
    var pins: [CustomPinnedURL]
    var lastActiveID: String?

    static let empty = CustomPinnedURLSnapshot(
        isEnabled: false,
        pins: [],
        lastActiveID: nil
    )

    var lastActivePin: CustomPinnedURL? {
        guard let lastActiveID else { return nil }
        return pins.first { $0.id == lastActiveID }
    }
}

struct CustomPinnedURLStore {
    static let enabledKey = "customPinnedURLsEnabled"
    static let pinsKey = "customPinnedURLs"
    static let lastActiveIDKey = "customPinnedURLLastActiveID"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CustomPinnedURLSnapshot {
        CustomPinnedURLSnapshot(
            isEnabled: loadEnabled(),
            pins: loadPins(),
            lastActiveID: loadLastActiveID()
        )
    }

    func save(_ snapshot: CustomPinnedURLSnapshot) {
        saveEnabled(snapshot.isEnabled)
        savePins(snapshot.pins)
        saveLastActiveID(snapshot.lastActiveID)
    }

    func loadEnabled() -> Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    func saveEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }

    func loadPins() -> [CustomPinnedURL] {
        guard let data = defaults.data(forKey: Self.pinsKey),
              let pins = try? decoder.decode([CustomPinnedURL].self, from: data)
        else {
            return []
        }
        return Array(pins.prefix(CustomPinnedURLPolicy.pinLimit))
    }

    func savePins(_ pins: [CustomPinnedURL]) {
        let limited = Array(pins.prefix(CustomPinnedURLPolicy.pinLimit))
        guard let data = try? encoder.encode(limited) else { return }
        defaults.set(data, forKey: Self.pinsKey)
    }

    func loadLastActiveID() -> String? {
        defaults.string(forKey: Self.lastActiveIDKey)
    }

    func saveLastActiveID(_ id: String?) {
        if let id, !id.isEmpty {
            defaults.set(id, forKey: Self.lastActiveIDKey)
        } else {
            defaults.removeObject(forKey: Self.lastActiveIDKey)
        }
    }
}
