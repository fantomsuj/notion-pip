import Foundation
import SwiftData

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
