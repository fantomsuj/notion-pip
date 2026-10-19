import Foundation
import SwiftData

/// Frozen copy of `RecentPageModel` as first shipped in `PerchSchemaV1`. Never edit
/// it: older schema versions reference it directly, so a change here silently
/// changes those versions and breaks migration for people upgrading. To change
/// the model, add a new namespace, point the newest schema and the typealias at
/// it, and add a migration stage.
enum RecentPageSchemaV1 {
    @Model
    final class RecentPageModel {
        @Attribute(.unique) var stableID: String
        var canonicalURL: String
        var displayTitle: String?
        var visitedAt: Date

        init(stableID: String, canonicalURL: String, displayTitle: String?, visitedAt: Date) {
            self.stableID = stableID
            self.canonicalURL = canonicalURL
            self.displayTitle = displayTitle
            self.visitedAt = visitedAt
        }
    }
}

typealias RecentPageModel = RecentPageSchemaV1.RecentPageModel
