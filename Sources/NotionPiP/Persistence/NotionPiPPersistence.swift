import Foundation
import SwiftData

enum NotionPiPPersistence {
    static func makeContainer(
        storeURL: URL? = nil,
        inMemory: Bool = false,
        applicationSupportDirectory: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NotionPiPSchemaV4.self)
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
            let supportDirectory: URL
            if let applicationSupportDirectory {
                supportDirectory = applicationSupportDirectory
            } else {
                supportDirectory = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            }
            let appDirectory = supportDirectory.appendingPathComponent(
                "com.fantomsuj.NotionPiP",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: appDirectory,
                withIntermediateDirectories: true
            )
            let appStoreURL = appDirectory.appendingPathComponent("NotionPiP.store")
            configuration = ModelConfiguration(
                schema: schema,
                url: appStoreURL,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: NotionPiPMigrationPlan.self,
            configurations: configuration
        )
    }
}
