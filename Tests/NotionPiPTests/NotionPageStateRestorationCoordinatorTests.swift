import Foundation
import XCTest
@testable import NotionPiP

@MainActor
final class NotionPageStateRestorationCoordinatorTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"
    private let thirdPageID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    func testInteractionStatesAreBoundedLRUAndConsumedOnce() throws {
        let coordinator = NotionPageStateRestorationCoordinator(interactionCapacity: 2)
        let first = try makePage(id: firstPageID)
        let second = try makePage(id: secondPageID)
        let third = try makePage(id: thirdPageID)
        let firstState = InteractionStateSentinel()
        let secondState = InteractionStateSentinel()
        let newerFirstState = InteractionStateSentinel()
        let thirdState = InteractionStateSentinel()

        _ = coordinator.capture(
            page: first,
            currentURL: first.canonicalURL,
            interactionState: firstState,
            now: Date(timeIntervalSince1970: 1)
        )
        _ = coordinator.capture(
            page: second,
            currentURL: second.canonicalURL,
            interactionState: secondState,
            now: Date(timeIntervalSince1970: 2)
        )
        _ = coordinator.capture(
            page: first,
            currentURL: first.canonicalURL,
            interactionState: newerFirstState,
            now: Date(timeIntervalSince1970: 3)
        )
        _ = coordinator.capture(
            page: third,
            currentURL: third.canonicalURL,
            interactionState: thirdState,
            now: Date(timeIntervalSince1970: 4)
        )

        guard case .load = coordinator.restorationPlan(for: second) else {
            return XCTFail("Expected the least-recent interaction state to be evicted")
        }
        guard case let .interactionState(value) = coordinator.restorationPlan(for: first) else {
            return XCTFail("Expected the refreshed interaction state")
        }
        XCTAssertTrue(value as AnyObject === newerFirstState)
        guard case .load = coordinator.restorationPlan(for: first) else {
            return XCTFail("Expected interaction state to be consumed exactly once")
        }
    }

    func testDurablePlanLoadsLastURLAndConsumesScrollAfterFinish() throws {
        let coordinator = NotionPageStateRestorationCoordinator()
        let page = try makePage(id: firstPageID)
        let lastURL = try XCTUnwrap(
            URL(string: "\(page.canonicalURL.absoluteString)?pvs=4")
        )
        let restoration = try DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: lastURL,
            scrollX: 3,
            scrollY: 400,
            scrollProgress: 0.6,
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        coordinator.prepareActivation(of: page, restoration: restoration)

        guard case let .load(url, isDurableRestoration) = coordinator.restorationPlan(for: page)
        else {
            return XCTFail("Expected a durable load plan")
        }
        XCTAssertEqual(url, lastURL)
        XCTAssertTrue(isDurableRestoration)
        XCTAssertEqual(coordinator.takePendingScrollRestoration(for: page.pageID), restoration)
        XCTAssertNil(coordinator.takePendingScrollRestoration(for: page.pageID))
    }

    func testCaptureUsesLatestScrollAndInjectedTimestamp() throws {
        let coordinator = NotionPageStateRestorationCoordinator()
        let page = try makePage(id: firstPageID)
        let timestamp = Date(timeIntervalSince1970: 42)
        coordinator.recordScroll(
            NotionScrollSnapshot(x: 5, y: 250, progress: 0.75),
            pageID: page.pageID
        )

        let restoration = try XCTUnwrap(
            coordinator.capture(
                page: page,
                currentURL: page.canonicalURL,
                interactionState: nil,
                now: timestamp
            )
        )

        XCTAssertEqual(restoration.pageID, page.pageID)
        XCTAssertEqual(restoration.lastURL, page.canonicalURL)
        XCTAssertEqual(restoration.scrollX, 5)
        XCTAssertEqual(restoration.scrollY, 250)
        XCTAssertEqual(restoration.scrollProgress, 0.75)
        XCTAssertEqual(restoration.updatedAt, timestamp)
    }

    func testFailedDurableRestorationFallsBackToCanonicalExactlyOnce() throws {
        let coordinator = NotionPageStateRestorationCoordinator()
        let page = try makePage(id: firstPageID)
        let lastURL = try XCTUnwrap(
            URL(string: "\(page.canonicalURL.absoluteString)?pvs=4")
        )
        let restoration = try DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: lastURL,
            scrollX: 0,
            scrollY: 10,
            scrollProgress: 0.2,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        coordinator.prepareActivation(of: page, restoration: restoration)
        _ = coordinator.restorationPlan(for: page)

        XCTAssertEqual(
            coordinator.canonicalFallbackAfterFailedDurableRestoration(for: page),
            page.canonicalURL
        )
        XCTAssertNil(coordinator.canonicalFallbackAfterFailedDurableRestoration(for: page))
        XCTAssertNil(coordinator.takePendingScrollRestoration(for: page.pageID))
    }

    func testRendererTerminationClearsPageStateAndResetsCanonicalProvenance() throws {
        let coordinator = NotionPageStateRestorationCoordinator()
        let page = try makePage(id: firstPageID)
        let state = InteractionStateSentinel()
        _ = coordinator.capture(
            page: page,
            currentURL: page.canonicalURL,
            interactionState: state,
            now: Date(timeIntervalSince1970: 1)
        )
        coordinator.prepareActivation(of: page, restoration: nil)

        coordinator.rendererDidTerminate(page: page)

        guard case let .load(url, isDurable) = coordinator.restorationPlan(for: page) else {
            return XCTFail("Expected canonical recovery after renderer termination")
        }
        XCTAssertEqual(url, page.canonicalURL)
        XCTAssertFalse(isDurable)
    }

    private func makePage(id: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Page-\(id)"))
        )
    }
}

private final class InteractionStateSentinel {}
