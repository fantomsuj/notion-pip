import XCTest
@testable import NotionPiP

@MainActor
final class PerformanceSignposterTests: XCTestCase {
    func testFirstOnlyOperationReturnsOneTokenAndSafelyIgnoresRepeatedEnds() {
        let signposter = AppPerformanceSignposter()

        let token = signposter.begin(.coldLaunchToReady)
        let duplicateToken = signposter.begin(.coldLaunchToReady)

        XCTAssertNotNil(token)
        XCTAssertNil(duplicateToken)

        signposter.end(token, outcome: .success)
        signposter.end(token, outcome: .failure)
        signposter.end(nil, outcome: .cancelled)
    }

    func testRepeatableOperationReturnsDistinctTokensForEveryInterval() throws {
        let signposter = AppPerformanceSignposter()

        let first = try XCTUnwrap(signposter.begin(.webViewEviction))
        let second = try XCTUnwrap(signposter.begin(.webViewEviction))

        XCTAssertNotEqual(first, second)
        signposter.end(first, outcome: .success)
        signposter.end(second, outcome: .failure)
    }
}

@MainActor
final class PerformanceSignposterSpy: PerformanceSignposting {
    private let tokenSource = AppPerformanceSignposter()
    private(set) var beginCalls: [PerformanceOperation] = []
    private(set) var beginRecords: [
        (operation: PerformanceOperation, token: PerformanceIntervalToken?)
    ] = []
    private(set) var endCalls: [
        (token: PerformanceIntervalToken?, outcome: PerformanceOutcome, metadata: PerformanceMetadata)
    ] = []

    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken? {
        beginCalls.append(operation)
        let token = tokenSource.begin(operation)
        beginRecords.append((operation, token))
        return token
    }

    func end(
        _ token: PerformanceIntervalToken?,
        outcome: PerformanceOutcome,
        metadata: PerformanceMetadata
    ) {
        endCalls.append((token, outcome, metadata))
        tokenSource.end(token, outcome: outcome, metadata: metadata)
    }
}
