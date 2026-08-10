import SwiftData
import XCTest
@testable import NotionPiP

final class RepositoryModelActorTests: XCTestCase {
    func testRepositoriesConformToModelActor() {
        assertModelActor(PageRepository.self)
    }

    private func assertModelActor<Repository: ModelActor>(_: Repository.Type) {}
}
