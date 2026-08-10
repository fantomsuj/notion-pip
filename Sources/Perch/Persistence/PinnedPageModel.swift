import Foundation
import SwiftData

enum PinnedPageSchemaV3 {
    @Model
    final class PinnedPageModel {
        @Attribute(.unique) var stableID: String
        var canonicalURL: String
        var displayTitle: String?
        var pinnedAt: Date

        init(stableID: String, canonicalURL: String, displayTitle: String?, pinnedAt: Date) {
            self.stableID = stableID
            self.canonicalURL = canonicalURL
            self.displayTitle = displayTitle
            self.pinnedAt = pinnedAt
        }
    }
}

enum PinnedPageSchemaV4 {
    @Model
    final class PinnedPageModel {
        @Attribute(.unique) var stableID: String
        var canonicalURL: String
        var displayTitle: String?
        var role: String?
        var pinnedAt: Date

        init(
            stableID: String,
            canonicalURL: String,
            displayTitle: String?,
            role: String? = nil,
            pinnedAt: Date
        ) {
            self.stableID = stableID
            self.canonicalURL = canonicalURL
            self.displayTitle = displayTitle
            self.role = role
            self.pinnedAt = pinnedAt
        }
    }
}

typealias PinnedPageModel = PinnedPageSchemaV4.PinnedPageModel
