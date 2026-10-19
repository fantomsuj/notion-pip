import Foundation
import SwiftData

/// Frozen copy of `PageRestorationModel` as first shipped in `PerchSchemaV3`. Never edit
/// it: older schema versions reference it directly, so a change here silently
/// changes those versions and breaks migration for people upgrading. To change
/// the model, add a new namespace, point the newest schema and the typealias at
/// it, and add a migration stage.
enum PageRestorationSchemaV3 {
    @Model
    final class PageRestorationModel {
        @Attribute(.unique) var stableID: String
        var lastURL: String
        var scrollX: Double
        var scrollY: Double
        var scrollProgress: Double
        var updatedAt: Date

        init(
            stableID: String,
            lastURL: String,
            scrollX: Double,
            scrollY: Double,
            scrollProgress: Double,
            updatedAt: Date
        ) {
            self.stableID = stableID
            self.lastURL = lastURL
            self.scrollX = scrollX
            self.scrollY = scrollY
            self.scrollProgress = scrollProgress
            self.updatedAt = updatedAt
        }
    }
}

typealias PageRestorationModel = PageRestorationSchemaV3.PageRestorationModel
