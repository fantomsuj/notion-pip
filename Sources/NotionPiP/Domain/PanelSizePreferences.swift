import CoreGraphics
import Foundation

struct PanelContentSize: Codable, Equatable, Hashable, Sendable {
    static let minimumWidth = 360.0
    static let minimumHeight = 420.0
    static let maximumDimension = 4_096.0

    let width: Double
    let height: Double

    init(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite else {
            throw PanelSizePreferencesError.nonFiniteDimensions
        }
        guard width >= Self.minimumWidth, height >= Self.minimumHeight else {
            throw PanelSizePreferencesError.dimensionsBelowMinimum(
                minimumWidth: Self.minimumWidth,
                minimumHeight: Self.minimumHeight
            )
        }
        guard width <= Self.maximumDimension, height <= Self.maximumDimension else {
            throw PanelSizePreferencesError.dimensionsAboveMaximum(
                maximum: Self.maximumDimension
            )
        }

        self.width = width
        self.height = height
    }

    init(_ size: CGSize) throws {
        try self.init(width: Double(size.width), height: Double(size.height))
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: container.decode(Double.self, forKey: .width),
            height: container.decode(Double.self, forKey: .height)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }
}

enum BuiltInPanelSizePreset:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Identifiable,
    Sendable
{
    case compact
    case comfortable
    case wide

    var id: PanelSizePresetID {
        .builtIn(self)
    }

    var name: String {
        switch self {
        case .compact:
            "Compact"
        case .comfortable:
            "Comfortable"
        case .wide:
            "Wide"
        }
    }

    func contentSize(forScreenSize screenSize: CGSize) -> PanelContentSize {
        switch self {
        case .compact:
            return PanelContentSize(uncheckedWidth: 420, height: 520)
        case .comfortable:
            let screenWidth = Double(screenSize.width)
            let screenHeight = Double(screenSize.height)
            return PanelContentSize(
                uncheckedWidth: Self.clamp(
                    screenWidth.isFinite ? screenWidth * 0.34 : 480,
                    minimum: 480,
                    maximum: 560
                ),
                height: Self.clamp(
                    screenHeight.isFinite ? screenHeight * 0.70 : 560,
                    minimum: 560,
                    maximum: 720
                )
            )
        case .wide:
            return PanelContentSize(uncheckedWidth: 680, height: 720)
        }
    }

    private static func clamp(
        _ value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        min(max(value, minimum), maximum)
    }
}

enum PanelSizePresetID: Codable, Equatable, Hashable, Sendable {
    case builtIn(BuiltInPanelSizePreset)
    case custom(UUID)

    static let compact = Self.builtIn(.compact)
    static let comfortable = Self.builtIn(.comfortable)
    static let wide = Self.builtIn(.wide)

    var rawValue: String {
        switch self {
        case .builtIn(let preset):
            "builtin:\(preset.rawValue)"
        case .custom(let id):
            "custom:\(id.uuidString.lowercased())"
        }
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else {
            return nil
        }

        switch components[0] {
        case "builtin":
            guard let preset = BuiltInPanelSizePreset(rawValue: String(components[1])) else {
                return nil
            }
            self = .builtIn(preset)
        case "custom":
            guard let id = UUID(uuidString: String(components[1])) else {
                return nil
            }
            self = .custom(id)
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let id = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid panel size preset identifier."
            )
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CustomPanelSizePreset: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let maximumNameLength = 40

    let id: UUID
    let name: String
    let contentSize: PanelContentSize

    init(
        id: UUID = UUID(),
        name: String,
        contentSize: PanelContentSize
    ) throws {
        let normalizedName = Self.normalized(name)
        guard !normalizedName.isEmpty else {
            throw PanelSizePreferencesError.emptyName
        }
        guard normalizedName.count <= Self.maximumNameLength else {
            throw PanelSizePreferencesError.nameTooLong(
                maximum: Self.maximumNameLength
            )
        }
        guard contentSize.width.rounded() == contentSize.width,
            contentSize.height.rounded() == contentSize.height
        else {
            throw PanelSizePreferencesError.dimensionsMustBeWholePoints
        }

        self.id = id
        self.name = normalizedName
        self.contentSize = contentSize
    }

    fileprivate static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func uniquenessKey(_ name: String) -> String {
        normalized(name).folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case contentSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            contentSize: container.decode(
                PanelContentSize.self,
                forKey: .contentSize
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(contentSize, forKey: .contentSize)
    }
}

enum PanelSizePreset: Equatable, Hashable, Identifiable, Sendable {
    case builtIn(BuiltInPanelSizePreset)
    case custom(CustomPanelSizePreset)

    var id: PanelSizePresetID {
        switch self {
        case .builtIn(let preset):
            preset.id
        case .custom(let preset):
            .custom(preset.id)
        }
    }

    var name: String {
        switch self {
        case .builtIn(let preset):
            preset.name
        case .custom(let preset):
            preset.name
        }
    }

    func contentSize(forScreenSize screenSize: CGSize) -> PanelContentSize {
        switch self {
        case .builtIn(let preset):
            preset.contentSize(forScreenSize: screenSize)
        case .custom(let preset):
            preset.contentSize
        }
    }
}

struct PanelSizePreferences: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumCustomPresetCount = 12

    static let `default` = PanelSizePreferences(
        uncheckedVersion: currentVersion,
        defaultPresetID: .comfortable,
        customPresets: [],
        lastExplicitWorkingContentSize: nil
    )

    private(set) var version: Int
    private(set) var defaultPresetID: PanelSizePresetID
    private(set) var customPresets: [CustomPanelSizePreset]
    private(set) var lastExplicitWorkingContentSize: PanelContentSize?

    init(
        version: Int = Self.currentVersion,
        defaultPresetID: PanelSizePresetID = .comfortable,
        customPresets: [CustomPanelSizePreset] = [],
        lastExplicitWorkingContentSize: PanelContentSize? = nil
    ) throws {
        try Self.validate(
            version: version,
            defaultPresetID: defaultPresetID,
            customPresets: customPresets
        )
        self.version = version
        self.defaultPresetID = defaultPresetID
        self.customPresets = customPresets
        self.lastExplicitWorkingContentSize = lastExplicitWorkingContentSize
    }

    var presets: [PanelSizePreset] {
        BuiltInPanelSizePreset.allCases.map(PanelSizePreset.builtIn)
            + customPresets.map(PanelSizePreset.custom)
    }

    var defaultPreset: PanelSizePreset {
        preset(withID: defaultPresetID) ?? .builtIn(.comfortable)
    }

    func preset(withID id: PanelSizePresetID) -> PanelSizePreset? {
        switch id {
        case .builtIn(let preset):
            .builtIn(preset)
        case .custom(let id):
            customPresets.first(where: { $0.id == id }).map(PanelSizePreset.custom)
        }
    }

    @discardableResult
    mutating func addCustomPreset(
        id: UUID = UUID(),
        name: String,
        contentSize: PanelContentSize
    ) throws -> CustomPanelSizePreset {
        guard customPresets.count < Self.maximumCustomPresetCount else {
            throw PanelSizePreferencesError.customPresetLimitReached(
                maximum: Self.maximumCustomPresetCount
            )
        }
        guard !customPresets.contains(where: { $0.id == id }) else {
            throw PanelSizePreferencesError.duplicatePresetID(id)
        }

        let preset = try CustomPanelSizePreset(
            id: id,
            name: name,
            contentSize: contentSize
        )
        try ensureUniqueName(preset.name)
        customPresets.append(preset)
        return preset
    }

    mutating func updateCustomPreset(
        id: UUID,
        name: String,
        contentSize: PanelContentSize
    ) throws {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else {
            throw PanelSizePreferencesError.customPresetNotFound(id)
        }

        let preset = try CustomPanelSizePreset(
            id: id,
            name: name,
            contentSize: contentSize
        )
        try ensureUniqueName(preset.name, excluding: id)
        customPresets[index] = preset
    }

    @discardableResult
    mutating func deleteCustomPreset(id: UUID) -> Bool {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else {
            return false
        }

        customPresets.remove(at: index)
        if defaultPresetID == .custom(id) {
            defaultPresetID = .comfortable
        }
        return true
    }

    mutating func setDefaultPreset(id: PanelSizePresetID) throws {
        guard preset(withID: id) != nil else {
            throw PanelSizePreferencesError.presetNotFound(id)
        }
        defaultPresetID = id
    }

    mutating func setLastExplicitWorkingContentSize(_ contentSize: PanelContentSize?) {
        lastExplicitWorkingContentSize = contentSize
    }

    private init(
        uncheckedVersion: Int,
        defaultPresetID: PanelSizePresetID,
        customPresets: [CustomPanelSizePreset],
        lastExplicitWorkingContentSize: PanelContentSize?
    ) {
        version = uncheckedVersion
        self.defaultPresetID = defaultPresetID
        self.customPresets = customPresets
        self.lastExplicitWorkingContentSize = lastExplicitWorkingContentSize
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case defaultPresetID
        case customPresets
        case lastExplicitWorkingContentSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let defaultPresetID = try container.decode(
            PanelSizePresetID.self,
            forKey: .defaultPresetID
        )
        let customPresets = try container.decode(
            [CustomPanelSizePreset].self,
            forKey: .customPresets
        )
        let lastExplicitWorkingContentSize = try container.decodeIfPresent(
            PanelContentSize.self,
            forKey: .lastExplicitWorkingContentSize
        )

        try self.init(
            version: version,
            defaultPresetID: defaultPresetID,
            customPresets: customPresets,
            lastExplicitWorkingContentSize: lastExplicitWorkingContentSize
        )
    }

    private static func validate(
        version: Int,
        defaultPresetID: PanelSizePresetID,
        customPresets: [CustomPanelSizePreset]
    ) throws {
        guard version == currentVersion else {
            throw PanelSizePreferencesError.unsupportedVersion(version)
        }
        guard customPresets.count <= maximumCustomPresetCount else {
            throw PanelSizePreferencesError.customPresetLimitReached(
                maximum: maximumCustomPresetCount
            )
        }

        var ids = Set<UUID>()
        var names = Set(
            BuiltInPanelSizePreset.allCases.map {
                CustomPanelSizePreset.uniquenessKey($0.name)
            }
        )
        for preset in customPresets {
            guard ids.insert(preset.id).inserted else {
                throw PanelSizePreferencesError.duplicatePresetID(preset.id)
            }
            let nameKey = CustomPanelSizePreset.uniquenessKey(preset.name)
            guard names.insert(nameKey).inserted else {
                throw PanelSizePreferencesError.duplicateName(preset.name)
            }
        }

        if case .custom(let id) = defaultPresetID,
            !customPresets.contains(where: { $0.id == id })
        {
            throw PanelSizePreferencesError.presetNotFound(defaultPresetID)
        }
    }

    private func ensureUniqueName(_ name: String, excluding id: UUID? = nil) throws {
        let key = CustomPanelSizePreset.uniquenessKey(name)
        let reservedNames = BuiltInPanelSizePreset.allCases.map {
            CustomPanelSizePreset.uniquenessKey($0.name)
        }
        guard !reservedNames.contains(key),
            !customPresets.contains(where: {
                $0.id != id && CustomPanelSizePreset.uniquenessKey($0.name) == key
            })
        else {
            throw PanelSizePreferencesError.duplicateName(name)
        }
    }
}

enum PanelSizePreferencesError: Error, Equatable, Sendable {
    case nonFiniteDimensions
    case dimensionsBelowMinimum(minimumWidth: Double, minimumHeight: Double)
    case dimensionsAboveMaximum(maximum: Double)
    case dimensionsMustBeWholePoints
    case emptyName
    case nameTooLong(maximum: Int)
    case duplicateName(String)
    case duplicatePresetID(UUID)
    case customPresetLimitReached(maximum: Int)
    case customPresetNotFound(UUID)
    case presetNotFound(PanelSizePresetID)
    case unsupportedVersion(Int)
}

extension PanelContentSize {
    fileprivate init(uncheckedWidth width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
