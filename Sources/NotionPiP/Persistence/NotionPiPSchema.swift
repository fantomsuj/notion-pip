import SwiftData

enum NotionPiPSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftModel.self,
            CaptureRecordModel.self,
            PinnedPageModel.self,
            RecentPageModel.self,
        ]
    }
}

enum NotionPiPMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NotionPiPSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
