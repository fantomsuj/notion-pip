import XCTest
@testable import NotionPiP

final class PersonalIntegrationTokenTests: XCTestCase {
    func testInternalTokenIsAcceptedAndRedactedForPresentation() throws {
        let token = try PersonalIntegrationToken(validating: "ntn_1234567890abcdef")

        XCTAssertEqual(token.redactedDescription, "ntn_…cdef")
    }

    func testTokenWithoutInternalIntegrationPrefixIsRejected() {
        XCTAssertThrowsError(try PersonalIntegrationToken(validating: "secret_1234567890abcdef")) { error in
            XCTAssertEqual(error as? PersonalIntegrationTokenError, .unsupportedFormat)
        }
    }

    func testWhitespaceOnlyTokenIsRejected() {
        XCTAssertThrowsError(try PersonalIntegrationToken(validating: "   ")) { error in
            XCTAssertEqual(error as? PersonalIntegrationTokenError, .missing)
        }
    }
}
