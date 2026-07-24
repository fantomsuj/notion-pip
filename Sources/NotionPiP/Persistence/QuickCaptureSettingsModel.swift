import Foundation
import SwiftData

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
