import Foundation
import SwiftData

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
