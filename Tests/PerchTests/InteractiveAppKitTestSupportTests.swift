import XCTest

final class InteractiveAppKitTestSupportTests: XCTestCase {
    func testInteractiveAppKitTestsAreDisabledWithoutExplicitOptIn() {
        XCTAssertFalse(interactiveAppKitTestsEnabled(environment: [:]))
        XCTAssertFalse(
            interactiveAppKitTestsEnabled(
                environment: ["PERCH_RUN_INTERACTIVE_TESTS": "true"]
            )
        )
    }

    func testInteractiveAppKitTestsAreEnabledByDocumentedOptIn() {
        XCTAssertTrue(
            interactiveAppKitTestsEnabled(
                environment: ["PERCH_RUN_INTERACTIVE_TESTS": "1"]
            )
        )
    }
}
