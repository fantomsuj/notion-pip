import Foundation
import SwiftData

enum PerchPersistence {
    static func storeDirectory(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let supportDirectory = applicationSupportDirectory
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportDirectory.appendingPathComponent(
            "com.fantomsuj.Perch",
            isDirectory: true
        )
    }

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
            let appDirectory = storeDirectory(
                applicationSupportDirectory: applicationSupportDirectory
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
