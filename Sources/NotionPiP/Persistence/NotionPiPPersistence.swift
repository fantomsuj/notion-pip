import Foundation
import SwiftData

enum NotionPiPPersistence {
    static func makeContainer(
        storeURL: URL? = nil,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NotionPiPSchemaV5.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: NotionPiPMigrationPlan.self,
            configurations: configuration
        )
    }
}
