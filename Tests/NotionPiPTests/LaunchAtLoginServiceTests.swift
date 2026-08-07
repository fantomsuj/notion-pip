import ServiceManagement
import XCTest
@testable import NotionPiP

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testRegisteredSystemStatusIsEnabled() {
        let registration = TestLaunchAtLoginRegistration(status: .enabled)
        let service = LaunchAtLoginService(registration: registration)

        XCTAssertEqual(service.state, .registered)
        XCTAssertTrue(service.isRegistered)
    }

    func testUnregisteredSystemStatusIsDisabled() {
        let registration = TestLaunchAtLoginRegistration(status: .notRegistered)
        let service = LaunchAtLoginService(registration: registration)

        XCTAssertEqual(service.state, .unregistered)
        XCTAssertFalse(service.isRegistered)
    }

    func testRequiresApprovalRemainsRegisteredAndCanOpenSystemSettings() {
        let registration = TestLaunchAtLoginRegistration(status: .requiresApproval)
        let service = LaunchAtLoginService(registration: registration)

        XCTAssertEqual(service.state, .requiresApproval)
        XCTAssertTrue(service.isRegistered)

        service.openSystemSettings()

        XCTAssertEqual(registration.openSystemSettingsCount, 1)
    }

    func testRegistrationFailureKeepsActualSystemStateAndPublishesFailure() {
        let registration = TestLaunchAtLoginRegistration(
            status: .notRegistered,
            registerError: TestRegistrationError.denied
        )
        let service = LaunchAtLoginService(registration: registration)

        service.setEnabled(true)

        XCTAssertEqual(registration.registerCount, 1)
        XCTAssertEqual(service.state, .unregistered)
        XCTAssertFalse(service.isRegistered)
        XCTAssertEqual(
            service.failureMessage,
            "Could not enable Launch at Login. Registration denied for test."
        )
    }

    func testUnregistrationFailureKeepsActualSystemStateAndPublishesFailure() {
        let registration = TestLaunchAtLoginRegistration(
            status: .enabled,
            unregisterError: TestRegistrationError.denied
        )
        let service = LaunchAtLoginService(registration: registration)

        service.setEnabled(false)

        XCTAssertEqual(registration.unregisterCount, 1)
        XCTAssertEqual(service.state, .registered)
        XCTAssertTrue(service.isRegistered)
        XCTAssertEqual(
            service.failureMessage,
            "Could not disable Launch at Login. Registration denied for test."
        )
    }

    func testSuccessfulEnableAndDisableReflectPostOperationSystemStatus() {
        let registration = TestLaunchAtLoginRegistration(status: .notRegistered)
        let service = LaunchAtLoginService(registration: registration)

        service.setEnabled(true)

        XCTAssertEqual(registration.registerCount, 1)
        XCTAssertEqual(service.state, .registered)

        service.setEnabled(false)

        XCTAssertEqual(registration.unregisterCount, 1)
        XCTAssertEqual(service.state, .unregistered)
    }

    func testRepeatedActionsDoNotRepeatSystemRegistrationCalls() {
        let registration = TestLaunchAtLoginRegistration(status: .enabled)
        let service = LaunchAtLoginService(registration: registration)

        service.setEnabled(true)
        service.setEnabled(true)

        XCTAssertEqual(registration.registerCount, 0)

        registration.status = .notRegistered
        service.refresh()
        service.setEnabled(false)
        service.setEnabled(false)

        XCTAssertEqual(registration.unregisterCount, 0)
    }

    func testRefreshRecoversFromExternalSystemStateChange() {
        let registration = TestLaunchAtLoginRegistration(status: .notRegistered)
        let service = LaunchAtLoginService(registration: registration)

        registration.status = .requiresApproval
        service.refresh()

        XCTAssertEqual(service.state, .requiresApproval)
        XCTAssertTrue(service.isRegistered)

        registration.status = .enabled
        service.refresh()

        XCTAssertEqual(service.state, .registered)
        XCTAssertTrue(service.isRegistered)

        registration.status = .notRegistered
        service.refresh()

        XCTAssertEqual(service.state, .unregistered)
        XCTAssertFalse(service.isRegistered)
    }

    func testNotFoundSystemStatusIsUnavailable() {
        let registration = TestLaunchAtLoginRegistration(status: .notFound)
        let service = LaunchAtLoginService(registration: registration)

        XCTAssertEqual(service.state, .unavailable)
        XCTAssertFalse(service.isRegistered)
    }

    func testNotFoundSystemStatusCanAttemptFreshRegistration() {
        let registration = TestLaunchAtLoginRegistration(status: .notFound)
        let service = LaunchAtLoginService(registration: registration)

        service.setEnabled(true)

        XCTAssertEqual(registration.registerCount, 1)
        XCTAssertEqual(service.state, .registered)
        XCTAssertTrue(service.isRegistered)
    }
}

@MainActor
private final class TestLaunchAtLoginRegistration: LaunchAtLoginRegistering {
    var status: SMAppService.Status
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0

    init(
        status: SMAppService.Status,
        registerError: (any Error)? = nil,
        unregisterError: (any Error)? = nil
    ) {
        self.status = status
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCount += 1
    }
}

private enum TestRegistrationError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Registration denied for test."
    }
}
