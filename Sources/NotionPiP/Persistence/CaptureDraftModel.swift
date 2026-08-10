import Foundation
import SwiftData

/// Legacy schema entity retained only to migrate pre-V5 stores.
@Model
final class CaptureDraftModel {
    @Attribute(.unique) var stableID: String
    var revision: Int
    var title: String
    var editorDocument: Data
    var sourceDocument: Data?
    var dispositionRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var captureRecordID: String?
    var returnDraftID: String?

    init(
        stableID: String,
        revision: Int,
        title: String,
        editorDocument: Data,
        sourceDocument: Data?,
        dispositionRawValue: String,
        createdAt: Date,
        updatedAt: Date,
        captureRecordID: String? = nil,
        returnDraftID: String? = nil
    ) {
        self.stableID = stableID
        self.revision = revision
        self.title = title
        self.editorDocument = editorDocument
        self.sourceDocument = sourceDocument
        self.dispositionRawValue = dispositionRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.captureRecordID = captureRecordID
        self.returnDraftID = returnDraftID
    }
}
