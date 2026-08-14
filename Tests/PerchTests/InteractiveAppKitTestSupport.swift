import Foundation
import XCTest

private let interactiveAppKitTestsEnvironmentKey = "PERCH_RUN_INTERACTIVE_TESTS"

func interactiveAppKitTestsEnabled(environment: [String: String]) -> Bool {
    environment[interactiveAppKitTestsEnvironmentKey] == "1"
}

func requireInteractiveAppKitTests(
    environment: [String: String] = ProcessInfo.processInfo.environment
) throws {
    try XCTSkipUnless(
        interactiveAppKitTestsEnabled(environment: environment),
        "This test presents real AppKit windows. Run with "
            + "PERCH_RUN_INTERACTIVE_TESTS=1 to include interactive UI tests."
    )
}
