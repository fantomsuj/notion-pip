import Foundation
import XCTest
@testable import NotionPiP

final class PageWorkingSetPolicyTests: XCTestCase {
    func testMutationCanonicalizesDeduplicatesOrdersAndSelectsRestorations() throws {
        let policy = PageWorkingSetPolicy(pinLimit: 2, recentLimit: 2)
        let older = try snapshot(id: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", time: 1)
        let newerDuplicate = try snapshot(id: older.pageID.uppercased(), time: 3)
        let newest = try snapshot(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", time: 4)
        let discarded = try snapshot(id: "cccccccccccccccccccccccccccccccc", time: 2)
        let workingSet = PageWorkingSetSnapshot(
            activePage: nil,
            pinnedPages: [older],
            recentPages: [discarded, newerDuplicate],
            restorations: []
        )

        let mutation = policy.recordVisit(newest, in: workingSet)

        XCTAssertEqual(mutation.pinnedPages, [older])
        XCTAssertEqual(mutation.recentPages, [newest, discarded])
        XCTAssertEqual(
            mutation.retainedRestorationIDs,
            Set([older.pageID, newest.pageID, discarded.pageID].map { $0.lowercased() })
        )
    }

    func testPinLimitFailureDoesNotProduceMutation() throws {
        let policy = PageWorkingSetPolicy(pinLimit: 1, recentLimit: 2)
        let pinned = try snapshot(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", time: 1)
        let candidate = try snapshot(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", time: 2)
        let workingSet = PageWorkingSetSnapshot(
            activePage: nil,
            pinnedPages: [pinned],
            recentPages: [],
            restorations: []
        )

        XCTAssertThrowsError(try policy.setPinned(true, page: candidate, in: workingSet)) {
            XCTAssertEqual($0 as? PageRepositoryError, .pinLimitReached(maximum: 1))
        }
    }

    private func snapshot(id: String, time: TimeInterval) throws -> StoredPageSnapshot {
        let page = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Page-\(id)"))
        )
        return StoredPageSnapshot(
            pageID: page.pageID,
            canonicalURL: page.canonicalURL,
            displayTitle: nil,
            timestamp: Date(timeIntervalSince1970: time)
        )
    }
}
