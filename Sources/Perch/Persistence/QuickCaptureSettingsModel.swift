import Foundation
import SwiftData

/// Legacy Quick Capture entity retained only for SwiftData schema compatibility.
/// The current app does not expose or read these rows.
///
/// Frozen copy of `QuickCaptureSettingsModel` as first shipped in `PerchSchemaV2`. Never edit
/// it: older schema versions reference it directly, so a change here silently
/// changes those versions and breaks migration for people upgrading. To change
/// the model, add a new namespace, point the newest schema and the typealias at
/// it, and add a migration stage.
enum QuickCaptureSettingsSchemaV2 {
    @Model
    final class QuickCaptureSettingsModel {
        @Attribute(.unique) var stableID: String
        var destinationKind: String
        var destinationID: String
        var displayTitle: String
        var updatedAt: Date

        init(
            stableID: String = "default",
            destinationKind: String,
            destinationID: String,
            displayTitle: String,
            updatedAt: Date
        ) {
            self.stableID = stableID
            self.destinationKind = destinationKind
            self.destinationID = destinationID
            self.displayTitle = displayTitle
            self.updatedAt = updatedAt
        }
    }
}

typealias QuickCaptureSettingsModel = QuickCaptureSettingsSchemaV2.QuickCaptureSettingsModel
