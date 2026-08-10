import Foundation
import SwiftData

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
