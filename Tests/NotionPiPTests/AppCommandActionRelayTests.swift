import XCTest
@testable import NotionPiP

@MainActor
final class AppCommandActionRelayTests: XCTestCase {
    func testReloadSavedPinInvokesConfiguredAction() {
        let relay = AppCommandActionRelay()
        var invocationCount = 0
        relay.reloadSavedPinAction = { invocationCount += 1 }

        relay.reloadSavedPin()

        XCTAssertEqual(invocationCount, 1)
    }
}
