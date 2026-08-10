import Foundation
import SwiftData

enum PerchPersistence {
    static func makeContainer(
        storeURL: URL? = nil,
        inMemory: Bool = false,
        applicationSupportDirectory: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PerchSchemaV4.self)
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
                "com.fantomsuj.Perch",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: appDirectory,
                withIntermediateDirectories: true
            )
            let appStoreURL = appDirectory.appendingPathComponent("Perch.store")
            configuration = ModelConfiguration(
                schema: schema,
                url: appStoreURL,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: PerchMigrationPlan.self,
            configurations: configuration
        )
    }
}
