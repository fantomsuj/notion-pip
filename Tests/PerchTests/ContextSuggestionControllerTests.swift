import Foundation
import XCTest
@testable import Perch

@MainActor
final class ContextSuggestionControllerTests: XCTestCase {
    func testStartDoesNotMonitorUntilPreferenceIsEnabled() {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor)

        controller.start()

        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertEqual(controller.permissionState, .disabled)
    }

    func testEnablingRequestsPermissionAndReportsDenial() {
        let monitor = ContextMonitorSpy(isAuthorized: false, requestResult: false)
        let preferences = ContextSuggestionPreferencesSpy()
        let controller = makeController(monitor: monitor, preferences: preferences)

        controller.setEnabled(true)

        XCTAssertEqual(monitor.requestCount, 1)
        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertEqual(controller.permissionState, .needsPermission)
        XCTAssertTrue(preferences.isEnabled)
    }

    func testChangedContextProducesLocalWorkingSetSuggestion() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor, enabled: true)
        controller.start()

        monitor.emit(githubContext)
        await settle()

        XCTAssertEqual(controller.suggestion?.label, "GitHub")
        XCTAssertEqual(controller.permissionState, .ready)
    }

    func testAcceptActivatesPageWithRestorationAndClearsCard() async throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let target = page()
        let restoration = try DurablePageRestoration(
            pageID: target.pageID,
            validatingLastURL: target.canonicalURL,
            scrollX: 0,
            scrollY: 420,
            scrollProgress: 0.5,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        var activation: (NotionPageReference, DurablePageRestoration?)?
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            restorations: [restoration],
            onActivate: { activation = ($0, $1) }
        )
        controller.start()
        monitor.emit(githubContext)
        await settle()

        controller.acceptSuggestion()

        let capturedActivation = try XCTUnwrap(activation)
        XCTAssertEqual(capturedActivation.0.pageID, target.pageID)
        XCTAssertEqual(capturedActivation.1, restoration)
        XCTAssertNil(controller.suggestion)
    }

    func testDismissSuppressesSameContextAndPageForThirtyMinutes() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let clock = TestDateProvider(Date(timeIntervalSince1970: 1_000))
        let controller = makeController(monitor: monitor, enabled: true, clock: clock)
        controller.start()
        monitor.emit(githubContext)
        await settle()
        XCTAssertNotNil(controller.suggestion)

        controller.dismissSuggestion()
        monitor.emit(mailContext)
        await settle()
        monitor.emit(githubContext)
        await settle()

        XCTAssertNil(controller.suggestion)

        clock.advance(by: 30 * 60 + 1)
        monitor.emit(mailContext)
        await settle()
        monitor.emit(githubContext)
        await settle()

        XCTAssertNotNil(controller.suggestion)
    }

    func testDisablingStopsMonitorAndDismissesSuggestion() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor, enabled: true)
        controller.start()
        monitor.emit(githubContext)
        await settle()

        controller.setEnabled(false)

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertNil(controller.suggestion)
        XCTAssertEqual(controller.permissionState, .disabled)
    }

    func testUnavailableContextDismissesSuggestion() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor, enabled: true)
        controller.start()
        monitor.emit(githubContext)
        await settle()
        XCTAssertNotNil(controller.suggestion)

        monitor.emit(nil)

        XCTAssertNil(controller.suggestion)
    }

    func testActivePageChangeDismissesSuggestion() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor, enabled: true)
        controller.start()
        monitor.emit(githubContext)
        await settle()

        controller.activePageDidChange()

        XCTAssertNil(controller.suggestion)
    }

    func testPermissionRevocationDismissesSuggestion() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor, enabled: true)
        controller.start()
        monitor.emit(githubContext)
        await settle()

        monitor.revokeAuthorization()

        XCTAssertNil(controller.suggestion)
        XCTAssertEqual(controller.permissionState, .needsPermission)
    }

    func testAcceptRevalidatesThatSuggestedPageIsNotAlreadyActive() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        var activePageID: String?
        var activationCount = 0
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: { activePageID },
            onActivate: { _, _ in activationCount += 1 }
        )
        controller.start()
        monitor.emit(githubContext)
        await settle()
        XCTAssertNotNil(controller.suggestion)

        activePageID = page().pageID
        controller.acceptSuggestion()

        XCTAssertEqual(activationCount, 0)
        XCTAssertNil(controller.suggestion)
    }

    private var githubContext: ContextSnapshot {
        ContextSnapshot(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            windowTitle: "GitHub",
            documentURL: URL(string: "https://github.com/fantomsuj/notion-pip")!
        )
    }

    private var mailContext: ContextSnapshot {
        ContextSnapshot(
            bundleIdentifier: "com.apple.mail",
            applicationName: "Mail",
            windowTitle: "Inbox",
            documentURL: nil
        )
    }

    private func page() -> StoredPageSnapshot {
        let pageID = "00000000000000000000000000000001"
        return StoredPageSnapshot(
            pageID: pageID,
            canonicalURL: URL(string: "https://www.notion.com/\(pageID)")!,
            displayTitle: "GitHub Notes",
            role: "GitHub",
            timestamp: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeController(
        monitor: ContextMonitorSpy,
        preferences: ContextSuggestionPreferencesSpy = ContextSuggestionPreferencesSpy(),
        enabled: Bool = false,
        clock: any DateProviding = TestDateProvider(Date(timeIntervalSince1970: 1_000)),
        restorations: [DurablePageRestoration] = [],
        activePageID: @escaping @MainActor () -> String? = { nil },
        onActivate: @escaping @MainActor (NotionPageReference, DurablePageRestoration?) -> Void = { _, _ in }
    ) -> ContextSuggestionController {
        preferences.isEnabled = enabled
        let store = InMemoryPageWorkingSetStore(
            snapshot: PageWorkingSetSnapshot(
                activePage: nil,
                pinnedPages: [page()],
                recentPages: [],
                restorations: restorations
            )
        )
        return ContextSuggestionController(
            monitor: monitor,
            store: store,
            preferenceStore: preferences,
            clock: clock,
            activePageID: activePageID,
            onActivate: onActivate
        )
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class ContextMonitorSpy: ContextMonitoring {
    var onSnapshot: (@MainActor (ContextSnapshot?) -> Void)?
    var onAuthorizationChange: (@MainActor (Bool) -> Void)?
    var isAuthorized: Bool
    var requestResult: Bool
    private(set) var requestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(isAuthorized: Bool, requestResult: Bool? = nil) {
        self.isAuthorized = isAuthorized
        self.requestResult = requestResult ?? isAuthorized
    }

    func requestAccess() -> Bool {
        requestCount += 1
        isAuthorized = requestResult
        return requestResult
    }

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func emit(_ snapshot: ContextSnapshot?) { onSnapshot?(snapshot) }
    func revokeAuthorization() {
        isAuthorized = false
        onAuthorizationChange?(false)
    }
}

@MainActor
private final class ContextSuggestionPreferencesSpy: ContextSuggestionPreferenceStoring {
    var isEnabled = false

    func load() -> Bool { isEnabled }
    func save(_ enabled: Bool) { isEnabled = enabled }
}
