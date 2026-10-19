import SwiftData

// Every schema version lists frozen, namespaced model types (for example
// `RecentPageSchemaV1.RecentPageModel`), never the live typealiases. A version
// must keep describing exactly what shipped, so changing a model means adding
// a new namespaced copy, a new schema version, and a migration stage, and
// leaving the older copies untouched. `SchemaMigrationTests` pins every
// version's entities and attributes so an accidental edit fails a test.

enum PerchSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftSchemaV1.CaptureDraftModel.self,
            CaptureRecordSchemaV1.CaptureRecordModel.self,
            PinnedPageSchemaV3.PinnedPageModel.self,
            RecentPageSchemaV1.RecentPageModel.self,
        ]
    }
}

enum PerchSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftSchemaV1.CaptureDraftModel.self,
            CaptureRecordSchemaV1.CaptureRecordModel.self,
            PinnedPageSchemaV3.PinnedPageModel.self,
            RecentPageSchemaV1.RecentPageModel.self,
            QuickCaptureSettingsSchemaV2.QuickCaptureSettingsModel.self,
        ]
    }
}

enum PerchSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftSchemaV1.CaptureDraftModel.self,
            CaptureRecordSchemaV1.CaptureRecordModel.self,
            PinnedPageSchemaV3.PinnedPageModel.self,
            RecentPageSchemaV1.RecentPageModel.self,
            QuickCaptureSettingsSchemaV2.QuickCaptureSettingsModel.self,
            ActivePageSchemaV3.ActivePageModel.self,
            PageRestorationSchemaV3.PageRestorationModel.self,
        ]
    }
}

enum PerchSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            CaptureDraftSchemaV1.CaptureDraftModel.self,
            CaptureRecordSchemaV1.CaptureRecordModel.self,
            PinnedPageSchemaV4.PinnedPageModel.self,
            RecentPageSchemaV1.RecentPageModel.self,
            QuickCaptureSettingsSchemaV2.QuickCaptureSettingsModel.self,
            ActivePageSchemaV3.ActivePageModel.self,
            PageRestorationSchemaV3.PageRestorationModel.self,
        ]
    }
}

enum PerchSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PinnedPageSchemaV4.PinnedPageModel.self,
            RecentPageSchemaV1.RecentPageModel.self,
            ActivePageSchemaV3.ActivePageModel.self,
            PageRestorationSchemaV3.PageRestorationModel.self,
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
            PerchSchemaV5.self,
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
            .lightweight(
                fromVersion: PerchSchemaV4.self,
                toVersion: PerchSchemaV5.self
            ),
        ]
    }
}
