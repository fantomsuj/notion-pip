import XCTest
@testable import Perch

final class QuickCopyCandidateBufferTests: XCTestCase {
    func testFIFORejectsNewestCandidateAtCapacityWithoutMutatingAcceptedOrder() {
        var buffer = QuickCopyCandidateBuffer(capacity: 2)
        let alpha = candidate("alpha", sequence: 1)
        let beta = candidate("beta", sequence: 2)
        let gamma = candidate("gamma", sequence: 3)

        XCTAssertEqual(buffer.enqueue(alpha), .accepted)
        XCTAssertEqual(buffer.enqueue(beta), .accepted)
        XCTAssertEqual(buffer.enqueue(gamma), .atCapacity)
        XCTAssertEqual(buffer.capacity, 2)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.front, alpha)
        XCTAssertEqual(buffer.dequeue(), alpha)
        XCTAssertEqual(buffer.dequeue(), beta)
        XCTAssertNil(buffer.dequeue())
    }

    func testFIFOReusesVacatedSlotsAcrossWraparound() {
        var buffer = QuickCopyCandidateBuffer(capacity: 2)
        let alpha = candidate("alpha", sequence: 1)
        let beta = candidate("beta", sequence: 2)
        let gamma = candidate("gamma", sequence: 3)

        XCTAssertEqual(buffer.enqueue(alpha), .accepted)
        XCTAssertEqual(buffer.enqueue(beta), .accepted)
        XCTAssertEqual(buffer.dequeue(), alpha)
        XCTAssertEqual(buffer.enqueue(gamma), .accepted)

        XCTAssertEqual(buffer.dequeue(), beta)
        XCTAssertEqual(buffer.dequeue(), gamma)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testRemoveAllReleasesLogicalContentsAndRetainsConfiguredCapacity() {
        var buffer = QuickCopyCandidateBuffer(capacity: 2)
        XCTAssertEqual(buffer.enqueue(candidate("alpha", sequence: 1)), .accepted)
        XCTAssertEqual(buffer.enqueue(candidate("beta", sequence: 2)), .accepted)

        buffer.removeAll()

        XCTAssertEqual(buffer.capacity, 2)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.front)
        XCTAssertEqual(buffer.enqueue(candidate("gamma", sequence: 3)), .accepted)
        XCTAssertEqual(buffer.front?.text, "gamma")
    }

    func testNonpositiveCapacityStillRetainsOneRetrySlot() {
        var buffer = QuickCopyCandidateBuffer(capacity: 0)

        XCTAssertEqual(buffer.capacity, 1)
        XCTAssertEqual(buffer.enqueue(candidate("alpha", sequence: 1)), .accepted)
        XCTAssertEqual(buffer.enqueue(candidate("beta", sequence: 2)), .atCapacity)
    }

    private func candidate(_ text: String, sequence: UInt64) -> QuickCopyCandidate {
        QuickCopyCandidate(
            text: text,
            source: QuickCopySource(processID: 7, applicationName: "Editor"),
            sequence: sequence
        )
    }
}
