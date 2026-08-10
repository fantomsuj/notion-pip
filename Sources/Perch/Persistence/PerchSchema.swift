import SwiftData

enum PerchSchemaV1: VersionedSchema {
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

enum PerchSchemaV2: VersionedSchema {
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

enum PerchSchemaV3: VersionedSchema {
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

enum PerchSchemaV4: VersionedSchema {
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

enum PerchMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            PerchSchemaV1.self,
            PerchSchemaV2.self,
            PerchSchemaV3.self,
            PerchSchemaV4.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: PerchSchemaV1.self,
                toVersion: PerchSchemaV2.self
            ),
            .lightweight(
                fromVersion: PerchSchemaV2.self,
                toVersion: PerchSchemaV3.self
            ),
            .lightweight(
                fromVersion: PerchSchemaV3.self,
                toVersion: PerchSchemaV4.self
            ),
        ]
    }
}
