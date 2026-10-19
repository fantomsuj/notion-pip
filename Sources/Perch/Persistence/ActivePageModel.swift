import Foundation
import SwiftData

/// Frozen copy of `ActivePageModel` as first shipped in `PerchSchemaV3`. Never edit
/// it: older schema versions reference it directly, so a change here silently
/// changes those versions and breaks migration for people upgrading. To change
/// the model, add a new namespace, point the newest schema and the typealias at
/// it, and add a migration stage.
enum ActivePageSchemaV3 {
    @Model
    final class ActivePageModel {
        @Attribute(.unique) var stableID: String
        var pageID: String
        var canonicalURL: String
        var displayTitle: String?
        var updatedAt: Date

        init(
            stableID: String = "active",
            pageID: String,
            canonicalURL: String,
            displayTitle: String?,
            updatedAt: Date
        ) {
            self.stableID = stableID
            self.pageID = pageID
            self.canonicalURL = canonicalURL
            self.displayTitle = displayTitle
            self.updatedAt = updatedAt
        }
    }
}

typealias ActivePageModel = ActivePageSchemaV3.ActivePageModel
