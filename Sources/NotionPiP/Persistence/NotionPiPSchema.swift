import SwiftData

enum NotionPiPSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftModel.self,
            CaptureRecordModel.self,
            PinnedPageSchemaV3.PinnedPageModel.self,
            RecentPageModel.self,
        ]
    }
}

enum NotionPiPSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftModel.self,
            CaptureRecordModel.self,
            PinnedPageSchemaV3.PinnedPageModel.self,
            RecentPageModel.self,
            QuickCaptureSettingsModel.self,
        ]
    }
}

enum NotionPiPSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftModel.self,
            CaptureRecordModel.self,
            PinnedPageSchemaV3.PinnedPageModel.self,
            RecentPageModel.self,
            QuickCaptureSettingsModel.self,
            ActivePageModel.self,
            PageRestorationModel.self,
        ]
    }
}

enum NotionPiPSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftModel.self,
            CaptureRecordModel.self,
            PinnedPageModel.self,
            RecentPageModel.self,
            QuickCaptureSettingsModel.self,
            ActivePageModel.self,
            PageRestorationModel.self,
        ]
    }
}

enum NotionPiPSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PinnedPageModel.self,
            RecentPageModel.self,
            ActivePageModel.self,
            PageRestorationModel.self,
        ]
    }
}

enum NotionPiPMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            NotionPiPSchemaV1.self,
            NotionPiPSchemaV2.self,
            NotionPiPSchemaV3.self,
            NotionPiPSchemaV4.self,
            NotionPiPSchemaV5.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: NotionPiPSchemaV1.self,
                toVersion: NotionPiPSchemaV2.self
            ),
            .lightweight(
                fromVersion: NotionPiPSchemaV2.self,
                toVersion: NotionPiPSchemaV3.self
            ),
            .lightweight(
                fromVersion: NotionPiPSchemaV3.self,
                toVersion: NotionPiPSchemaV4.self
            ),
            .lightweight(
                fromVersion: NotionPiPSchemaV4.self,
                toVersion: NotionPiPSchemaV5.self
            ),
        ]
    }
}
