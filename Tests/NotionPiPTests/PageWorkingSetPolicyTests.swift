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

    func testOrderedUniqueKeepsNewestCaseVariantAndUsesStableTieBreak() throws {
        let policy = PageWorkingSetPolicy(pinLimit: 7, recentLimit: 7)
        let older = try snapshot(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", time: 1)
        let newerDuplicate = StoredPageSnapshot(
            pageID: older.pageID.uppercased(),
            canonicalURL: older.canonicalURL,
            displayTitle: "Newest duplicate",
            timestamp: Date(timeIntervalSince1970: 3)
        )
        let tieLow = try snapshot(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", time: 2)
        let tieHigh = try snapshot(id: "cccccccccccccccccccccccccccccccc", time: 2)

        let result = policy.orderedUnique([older, tieHigh, newerDuplicate, tieLow])

        XCTAssertEqual(
            result.map { $0.pageID.lowercased() },
            [newerDuplicate.pageID, tieLow.pageID, tieHigh.pageID].map { $0.lowercased() }
        )
        XCTAssertEqual(result.first?.displayTitle, "Newest duplicate")
    }

    func testSuccessfulPinAndRepinPreserveActivePageAndWorkingSet() throws {
        let policy = PageWorkingSetPolicy(pinLimit: 2, recentLimit: 2)
        let existingPin = try snapshot(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", time: 1)
        let candidate = try snapshot(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", time: 3)
        let otherRecent = try snapshot(id: "cccccccccccccccccccccccccccccccc", time: 2)
        let active = try snapshot(id: "dddddddddddddddddddddddddddddddd", time: 4)
        let workingSet = PageWorkingSetSnapshot(
            activePage: active,
            pinnedPages: [existingPin],
            recentPages: [candidate, otherRecent],
            restorations: []
        )

        let pinned = try policy.setPinned(true, page: candidate, in: workingSet)
        let repinned = try policy.setPinned(
            true,
            page: candidate,
            in: PageWorkingSetSnapshot(
                activePage: pinned.activePage,
                pinnedPages: pinned.pinnedPages,
                recentPages: pinned.recentPages,
                restorations: []
            )
        )

        XCTAssertEqual(pinned.activePage, active)
        XCTAssertEqual(pinned.pinnedPages, [candidate, existingPin])
        XCTAssertEqual(pinned.recentPages, [otherRecent])
        XCTAssertEqual(repinned, pinned)
    }

    func testUnpinMovesPageToNewestRecentAndUpdatesRestorationRetention() throws {
        let policy = PageWorkingSetPolicy(pinLimit: 2, recentLimit: 2)
        let existingPin = try snapshot(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", time: 1)
        let pinned = try snapshot(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", time: 3)
        let unpinned = StoredPageSnapshot(
            pageID: pinned.pageID,
            canonicalURL: pinned.canonicalURL,
            displayTitle: pinned.displayTitle,
            timestamp: Date(timeIntervalSince1970: 4)
        )
        let otherRecent = try snapshot(id: "cccccccccccccccccccccccccccccccc", time: 2)
        let workingSet = PageWorkingSetSnapshot(
            activePage: pinned,
            pinnedPages: [pinned, existingPin],
            recentPages: [otherRecent],
            restorations: []
        )

        let mutation = try policy.setPinned(false, page: unpinned, in: workingSet)

        XCTAssertEqual(mutation.activePage, pinned)
        XCTAssertEqual(mutation.pinnedPages, [existingPin])
        XCTAssertEqual(mutation.recentPages, [unpinned, otherRecent])
        XCTAssertEqual(
            mutation.retainedRestorationIDs,
            Set([existingPin.pageID, unpinned.pageID, otherRecent.pageID])
        )
    }

    func testInMemoryMutationDropsOnlyEvictedRestorations() async throws {
        let policy = PageWorkingSetPolicy(pinLimit: 1, recentLimit: 1)
        let evicted = try snapshot(id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", time: 1)
        let retained = try snapshot(id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", time: 2)
        let store = InMemoryPageWorkingSetStore(
            snapshot: PageWorkingSetSnapshot(
                activePage: evicted,
                pinnedPages: [],
                recentPages: [evicted],
                restorations: [
                    try restoration(for: evicted),
                    try restoration(for: retained),
                ]
            ),
            policy: policy
        )

        _ = await store.recordVisit(
            try NotionPageReference(validating: retained.canonicalURL)
        )
        let result = await store.workingSet()

        XCTAssertEqual(result.recentPages.map(\.pageID), [retained.pageID])
        XCTAssertEqual(result.restorations.map(\.pageID), [retained.pageID])
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

    private func restoration(
        for page: StoredPageSnapshot
    ) throws -> DurablePageRestoration {
        try DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: page.canonicalURL,
            scrollX: 0,
            scrollY: 0,
            scrollProgress: 0,
            updatedAt: page.timestamp
        )
    }
}
