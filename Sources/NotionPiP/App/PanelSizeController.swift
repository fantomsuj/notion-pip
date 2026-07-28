import Combine
import CoreGraphics
import Foundation

@MainActor
protocol PanelSizing: AnyObject {
    var hasPinnedPage: Bool { get }
    var currentPanelContentSize: CGSize { get }
    var sizingScreenSize: CGSize { get }
    var onManualResizeCompletion: (@MainActor (CGSize) -> Void)? { get set }
    var onPinnedPageAvailabilityChange: (@MainActor () -> Void)? { get set }

    @discardableResult
    func applyPanelContentSize(_ contentSize: CGSize) -> Bool
}

@MainActor
final class PanelSizeController: ObservableObject {
    @Published private(set) var preferences: PanelSizePreferences
    @Published private(set) var currentContentSize: CGSize?
    @Published private(set) var canApply = false
    @Published private(set) var validationMessage: String?

    let hadStoredPreferences: Bool
    var onManagePanelSizes: @MainActor () -> Void = {}

    private let store: any PanelSizePreferencesPersisting
    private weak var sizingTarget: (any PanelSizing)?

    init(store: any PanelSizePreferencesPersisting = PanelSizePreferencesStore()) {
        self.store = store
        if let storedPreferences = store.load() {
            preferences = storedPreferences
            hadStoredPreferences = true
        } else {
            preferences = .default
            hadStoredPreferences = false
        }
    }

    var presets: [PanelSizePreset] {
        preferences.presets
    }

    var defaultPresetID: PanelSizePresetID {
        preferences.defaultPresetID
    }

    var canSaveCurrentSize: Bool {
        currentContentSize != nil
            && preferences.customPresets.count < PanelSizePreferences.maximumCustomPresetCount
    }

    func bind(to sizingTarget: any PanelSizing) {
        self.sizingTarget = sizingTarget
        sizingTarget.onManualResizeCompletion = { [weak self] contentSize in
            self?.recordManualResizeCompletion(contentSize)
        }
        sizingTarget.onPinnedPageAvailabilityChange = { [weak self] in
            self?.refreshPanelState()
        }
        refreshPanelState()
    }

    func refreshPanelState() {
        currentContentSize = sizingTarget?.currentPanelContentSize
        canApply = sizingTarget?.hasPinnedPage == true
    }

    func displayName(for preset: PanelSizePreset) -> String {
        if preset.id == defaultPresetID {
            "\(preset.name) — Default"
        } else {
            preset.name
        }
    }

    func resolvedContentSize(for preset: PanelSizePreset) -> PanelContentSize {
        preset.contentSize(
            forScreenSize: sizingTarget?.sizingScreenSize
                ?? CGSize(width: 1_440, height: 900)
        )
    }

    @discardableResult
    func apply(_ id: PanelSizePresetID) -> Bool {
        guard canApply,
            let target = sizingTarget,
            let preset = preferences.preset(withID: id)
        else {
            return false
        }

        let contentSize = resolvedContentSize(for: preset)
        guard target.applyPanelContentSize(contentSize.cgSize) else {
            return false
        }

        currentContentSize = target.currentPanelContentSize
        updatePreferences { preferences in
            preferences.setLastExplicitWorkingContentSize(contentSize)
        }
        return true
    }

    @discardableResult
    func applyDefault() -> Bool {
        apply(defaultPresetID)
    }

    @discardableResult
    func resetToDefault() -> Bool {
        applyDefault()
    }

    func setDefault(_ id: PanelSizePresetID) {
        updatePreferences { preferences in
            try preferences.setDefaultPreset(id: id)
        }
    }

    @discardableResult
    func addCustomPreset(
        name: String,
        width: Double,
        height: Double
    ) -> CustomPanelSizePreset? {
        var addedPreset: CustomPanelSizePreset?
        updatePreferences { preferences in
            addedPreset = try preferences.addCustomPreset(
                name: name,
                contentSize: PanelContentSize(width: width, height: height)
            )
        }
        return addedPreset
    }

    func updateCustomPreset(
        id: UUID,
        name: String,
        width: Double,
        height: Double
    ) {
        updatePreferences { preferences in
            try preferences.updateCustomPreset(
                id: id,
                name: name,
                contentSize: PanelContentSize(width: width, height: height)
            )
        }
    }

    func deleteCustomPreset(id: UUID) {
        updatePreferences { preferences in
            _ = preferences.deleteCustomPreset(id: id)
        }
    }

    func managePanelSizes() {
        onManagePanelSizes()
    }

    func clearValidationMessage() {
        validationMessage = nil
    }

    private func recordManualResizeCompletion(_ contentSize: CGSize) {
        currentContentSize = contentSize
        do {
            let validatedSize = try PanelContentSize(contentSize)
            updatePreferences { preferences in
                preferences.setLastExplicitWorkingContentSize(validatedSize)
            }
        } catch {
            validationMessage = Self.message(for: error)
        }
    }

    private func updatePreferences(
        _ mutation: (inout PanelSizePreferences) throws -> Void
    ) {
        var updatedPreferences = preferences
        do {
            try mutation(&updatedPreferences)
            try store.save(updatedPreferences)
            preferences = updatedPreferences
            validationMessage = nil
        } catch {
            validationMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case PanelSizePreferencesError.nonFiniteDimensions:
            "Enter finite width and height values."
        case PanelSizePreferencesError.dimensionsBelowMinimum(let width, let height):
            "Sizes must be at least \(Int(width)) × \(Int(height)) points."
        case PanelSizePreferencesError.dimensionsAboveMaximum(let maximum):
            "Sizes cannot exceed \(Int(maximum)) points."
        case PanelSizePreferencesError.dimensionsMustBeWholePoints:
            "Custom sizes must use whole-point dimensions."
        case PanelSizePreferencesError.emptyName:
            "Enter a preset name."
        case PanelSizePreferencesError.nameTooLong(let maximum):
            "Preset names can contain at most \(maximum) characters."
        case PanelSizePreferencesError.duplicateName:
            "Preset names must be unique."
        case PanelSizePreferencesError.customPresetLimitReached(let maximum):
            "You can save up to \(maximum) custom presets."
        case PanelSizePreferencesError.presetNotFound,
            PanelSizePreferencesError.customPresetNotFound:
            "That preset is no longer available."
        default:
            "Panel size preferences could not be saved."
        }
    }
}
