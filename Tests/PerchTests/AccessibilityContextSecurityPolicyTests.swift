import ApplicationServices
import XCTest
@testable import Perch

final class AccessibilityContextSecurityPolicyTests: XCTestCase {
    func testSecureTextFieldSubroleIsRejected() {
        XCTAssertTrue(
            AccessibilityContextSecurityPolicy.isSecure(
                role: kAXTextFieldRole as String,
                subrole: kAXSecureTextFieldSubrole as String
            )
        )
    }

    func testSecureRoleIsRejectedCaseInsensitively() {
        XCTAssertTrue(
            AccessibilityContextSecurityPolicy.isSecure(
                role: "AXSecureInput",
                subrole: nil
            )
        )
    }

    func testOrdinaryTextFieldIsAllowed() {
        XCTAssertFalse(
            AccessibilityContextSecurityPolicy.isSecure(
                role: kAXTextFieldRole as String,
                subrole: nil
            )
        )
    }
}
