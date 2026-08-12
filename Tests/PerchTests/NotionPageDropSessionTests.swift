import AppKit
import Foundation
import XCTest
@testable import Perch

final class NotionPageDropSessionTests: XCTestCase {
    func testUpdateAdvertisesCopyForNewValidCopyCapableSequence() throws {
        var session = NotionPageDropSession()

        XCTAssertEqual(
            session.update(
                sequenceNumber: 41,
                candidate: try makeDrop(pageID: "0123456789abcdef0123456789abcdef"),
                sourceOperationMask: .copy
            ),
            .copy
        )
    }

    func testUpdateRejectsInvalidCandidateAndSourceWithoutCopy() throws {
        var session = NotionPageDropSession()

        XCTAssertEqual(
            session.update(
                sequenceNumber: 41,
                candidate: nil,
                sourceOperationMask: .copy
            ),
            []
        )
        XCTAssertEqual(
            session.update(
                sequenceNumber: 42,
                candidate: try makeDrop(pageID: "0123456789abcdef0123456789abcdef"),
                sourceOperationMask: .link
            ),
            []
        )
    }

    func testUpdateFreezesFirstCandidateForSequence() throws {
        let first = try makeDrop(pageID: "0123456789abcdef0123456789abcdef")
        let later = try makeDrop(pageID: "fedcba9876543210fedcba9876543210")
        var session = NotionPageDropSession()

        XCTAssertEqual(
            session.update(sequenceNumber: 41, candidate: first, sourceOperationMask: .copy),
            .copy
        )
        XCTAssertEqual(
            session.update(sequenceNumber: 41, candidate: later, sourceOperationMask: .copy),
            .copy
        )

        XCTAssertEqual(session.perform(sequenceNumber: 41), first)
    }

    func testCanPrepareAcceptsOnlyActiveSequence() throws {
        var session = NotionPageDropSession()
        _ = session.update(
            sequenceNumber: 41,
            candidate: try makeDrop(pageID: "0123456789abcdef0123456789abcdef"),
            sourceOperationMask: .copy
        )

        XCTAssertTrue(session.canPrepare(sequenceNumber: 41))
        XCTAssertFalse(session.canPrepare(sequenceNumber: 42))
    }

    func testPerformReturnsActiveDropOnceThenResets() throws {
        let drop = try makeDrop(pageID: "0123456789abcdef0123456789abcdef")
        var session = NotionPageDropSession()
        _ = session.update(sequenceNumber: 41, candidate: drop, sourceOperationMask: .copy)

        XCTAssertEqual(session.perform(sequenceNumber: 41), drop)
        XCTAssertNil(session.perform(sequenceNumber: 41))
        XCTAssertFalse(session.canPrepare(sequenceNumber: 41))
    }

    func testResetClearsActiveDropWithoutReturningIt() throws {
        var session = NotionPageDropSession()
        _ = session.update(
            sequenceNumber: 41,
            candidate: try makeDrop(pageID: "0123456789abcdef0123456789abcdef"),
            sourceOperationMask: .copy
        )

        session.reset()

        XCTAssertFalse(session.canPrepare(sequenceNumber: 41))
        XCTAssertNil(session.perform(sequenceNumber: 41))
    }

    private func makeDrop(pageID: String) throws -> NotionPageDrop {
        try NotionPageDrop(
            validating: try XCTUnwrap(URL(string: "https://www.notion.so/Project-\(pageID)")),
            sourceLabel: nil
        )
    }
}
