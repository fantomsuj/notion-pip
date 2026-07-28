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
}

@MainActor
final class PerformanceSignposterSpy: PerformanceSignposting {
    private let tokenSource = AppPerformanceSignposter()
    private(set) var beginCalls: [PerformanceOperation] = []
    private(set) var endCalls: [(token: PerformanceIntervalToken?, outcome: PerformanceOutcome)] = []

    func begin(_ operation: PerformanceOperation) -> PerformanceIntervalToken? {
        beginCalls.append(operation)
        return tokenSource.begin(operation)
    }

    func end(_ token: PerformanceIntervalToken?, outcome: PerformanceOutcome) {
        endCalls.append((token, outcome))
        tokenSource.end(token, outcome: outcome)
    }
}
