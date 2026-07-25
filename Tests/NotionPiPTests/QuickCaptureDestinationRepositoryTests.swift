import Foundation
import SwiftData
import XCTest
@testable import NotionPiP

final class QuickCaptureDestinationRepositoryTests: XCTestCase {
    func testDefaultDestinationCanBeSavedReplacedAndCleared() async throws {
        let repository = QuickCaptureDestinationRepository(
            container: try NotionPiPPersistence.makeContainer(inMemory: true)
        )
        let page = QuickCaptureDestination.pageParent(
            pageID: "page-1",
            title: "Inbox"
        )
        let dataSource = QuickCaptureDestination.dataSource(
            dataSourceID: "source-1",
            title: "Notes"
        )

        try await repository.replaceDefault(with: page)
        let storedPage = try await repository.defaultDestination()
        XCTAssertEqual(storedPage, page)

        try await repository.replaceDefault(with: dataSource)
        let storedDataSource = try await repository.defaultDestination()
        XCTAssertEqual(storedDataSource, dataSource)

        try await repository.clearDefault()
        let cleared = try await repository.defaultDestination()
        XCTAssertNil(cleared)
    }

    func testDestinationPersistsOnlyStableSelectionMetadata() async throws {
        let container = try NotionPiPPersistence.makeContainer(inMemory: true)
        let repository = QuickCaptureDestinationRepository(container: container)

        try await repository.replaceDefault(
            with: .dataSource(dataSourceID: "source-1", title: "Notes")
        )

        let context = ModelContext(container)
        let models = try context.fetch(FetchDescriptor<QuickCaptureSettingsModel>())
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(model.destinationKind, "data_source")
        XCTAssertEqual(model.destinationID, "source-1")
        XCTAssertEqual(model.displayTitle, "Notes")
    }
}
