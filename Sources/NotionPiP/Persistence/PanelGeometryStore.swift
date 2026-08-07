import Foundation

protocol PanelGeometryPersisting {
    func load() -> PanelGeometry?
    func save(_ geometry: PanelGeometry) throws
}

final class PanelGeometryStore: PanelGeometryPersisting {
    static let key = "panelGeometry"

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

    func load() -> PanelGeometry? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try? decoder.decode(PanelGeometry.self, from: data)
    }

    func save(_ geometry: PanelGeometry) throws {
        defaults.set(try encoder.encode(geometry), forKey: Self.key)
    }
}

final class TransientPanelGeometryStore: PanelGeometryPersisting {
    private var geometry: PanelGeometry?

    init(geometry: PanelGeometry? = nil) {
        self.geometry = geometry
    }

    func load() -> PanelGeometry? {
        geometry
    }

    func save(_ geometry: PanelGeometry) throws {
        self.geometry = geometry
    }
}
