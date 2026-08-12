import Foundation
import SwiftData

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
