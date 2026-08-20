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

    func testExactPageAutomaticallyActivatesWhenPerchIsEmpty() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            onActivate: activation.record
        )
        controller.start()

        controller.requestContextualReveal()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))

        XCTAssertEqual(activation.pages.map(\.pageID), [secondPageID])
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testPreparedSourceIsCapturedBeforeFocusAndUsedForLaterExactRead() throws {
        let source = ContextSourceIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )
        let monitor = ContextMonitorSpy(isAuthorized: true)
        monitor.sourceIdentity = source
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            onActivate: activation.record
        )
        controller.start()

        controller.prepareContextualRevealSource()
        monitor.sourceIdentity = nil
        controller.requestContextualReveal()

        XCTAssertEqual(monitor.exactCaptureSources, [source])
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))
        XCTAssertEqual(activation.pages.map(\.pageID), [secondPageID])
    }

    func testDiscardedPreparedSourceIsNotUsedByLaterReveal() {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        monitor.sourceIdentity = ContextSourceIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )
        let controller = makeController(monitor: monitor, enabled: true)
        controller.start()

        controller.prepareContextualRevealSource()
        controller.discardPreparedContextualRevealSource()
        controller.requestContextualReveal()

        XCTAssertEqual(monitor.exactCaptureCount, 1)
        XCTAssertTrue(monitor.exactCaptureSources.isEmpty)
    }

    func testDifferentExactPageOffersOpenHereWithoutReplacingCurrentPage() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: firstPageID)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read,
            onActivate: activation.record
        )
        controller.start()

        controller.requestContextualReveal()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))

        XCTAssertEqual(controller.contextualPageActionState.action?.page.pageID, secondPageID)
        XCTAssertEqual(controller.contextualPageActionState.action?.sourceApplicationName, "Safari")
        XCTAssertTrue(activation.pages.isEmpty)
    }

    func testSameExactPageDoesNotOfferOpenHere() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: firstPageID)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read,
            onActivate: activation.record
        )
        controller.start()

        controller.requestContextualReveal()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: firstPageID))

        XCTAssertNil(controller.contextualPageActionState.action)
        XCTAssertTrue(activation.pages.isEmpty)
    }

    func testOpenHereRevalidatesCurrentPageAndUsesNormalActivationCallback() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: firstPageID)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read,
            onActivate: activation.record
        )
        controller.start()
        controller.requestContextualReveal()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))

        controller.contextualPageActionState.accept()

        XCTAssertEqual(activation.pages.map(\.pageID), [secondPageID])
        XCTAssertEqual(activation.restorations.count, 1)
        XCTAssertNil(activation.restorations[0])
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testDismissalClearsActionAndNewerRevealCanReplaceIt() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: firstPageID)
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read
        )
        controller.start()
        controller.requestContextualReveal()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))

        controller.contextualPageActionState.dismiss()
        XCTAssertNil(controller.contextualPageActionState.action)

        let thirdPageID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        controller.requestContextualReveal()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: thirdPageID))

        XCTAssertEqual(controller.contextualPageActionState.action?.page.pageID, thirdPageID)
    }

    func testNewerRevealRejectsStaleExactCaptureResult() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: firstPageID)
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read
        )
        controller.start()

        controller.requestContextualReveal()
        controller.requestContextualReveal()
        monitor.completeExactCapture(at: 0, with: try exactSnapshot(pageID: secondPageID))
        XCTAssertNil(controller.contextualPageActionState.action)

        let newestPageID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        monitor.completeExactCapture(at: 0, with: try exactSnapshot(pageID: newestPageID))

        XCTAssertEqual(controller.contextualPageActionState.action?.page.pageID, newestPageID)
    }

    func testDeniedPermissionFallsBackWithoutStartingExactCapture() {
        let monitor = ContextMonitorSpy(isAuthorized: false, requestResult: false)
        let controller = makeController(monitor: monitor, enabled: true)
        var fallbackCount = 0
        controller.start()

        controller.requestContextualReveal {
            fallbackCount += 1
        }

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertEqual(monitor.exactCaptureCount, 0)
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testPermissionRevocationInvalidatesPendingCaptureAndFallsBack() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            onActivate: activation.record
        )
        var fallbackCount = 0
        controller.start()
        controller.requestContextualReveal {
            fallbackCount += 1
        }

        monitor.revokeAuthorization()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertTrue(activation.pages.isEmpty)
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testTerminatedSourceResultFallsBackAsNoContext() {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(monitor: monitor, enabled: true)
        var fallbackCount = 0
        controller.start()
        controller.requestContextualReveal {
            fallbackCount += 1
        }

        monitor.completeExactCapture(with: nil)

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testExactCaptureTimeoutFallsBackAsNoContext() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            exactCaptureTimeout: .zero
        )
        var fallbackCount = 0
        controller.start()
        controller.requestContextualReveal {
            fallbackCount += 1
        }

        await settle()

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testExplicitPageActivationInvalidatesPendingContextualReplacement() throws {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: nil)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read,
            onActivate: activation.record
        )
        var fallbackCount = 0
        controller.start()
        controller.requestContextualReveal {
            fallbackCount += 1
        }

        activePage.pageID = firstPageID
        controller.activePageDidChange()
        monitor.completeExactCapture(with: try exactSnapshot(pageID: secondPageID))

        XCTAssertTrue(activation.pages.isEmpty)
        XCTAssertEqual(fallbackCount, 0)
        XCTAssertNil(controller.contextualPageActionState.action)
    }

    func testAcceptRevalidatesThatSuggestedPageIsNotAlreadyActive() async {
        let monitor = ContextMonitorSpy(isAuthorized: true)
        let activePage = ContextualActivePageBox(pageID: nil)
        let activation = ContextualActivationRecorder()
        let controller = makeController(
            monitor: monitor,
            enabled: true,
            activePageID: activePage.read,
            onActivate: activation.record
        )
        controller.start()
        monitor.emit(githubContext)
        await settle()
        XCTAssertNotNil(controller.suggestion)

        activePage.pageID = page().pageID
        controller.acceptSuggestion()

        XCTAssertTrue(activation.pages.isEmpty)
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

    private func exactSnapshot(pageID: String) throws -> ContextSnapshot {
        ContextSnapshot(
            source: ContextSourceIdentity(
                processIdentifier: 42,
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari"
            ),
            exactPage: try NotionPageReference(
                validating: XCTUnwrap(
                    URL(string: "https://www.notion.com/Context-\(pageID)")
                )
            )
        )
    }

    private func makeController(
        monitor: ContextMonitorSpy,
        preferences: ContextSuggestionPreferencesSpy = ContextSuggestionPreferencesSpy(),
        enabled: Bool = false,
        clock: any DateProviding = TestDateProvider(Date(timeIntervalSince1970: 1_000)),
        exactCaptureTimeout: Duration = .seconds(1),
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
            exactCaptureTimeout: exactCaptureTimeout,
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
    private(set) var exactCaptureCount = 0
    var sourceIdentity: ContextSourceIdentity?
    private(set) var exactCaptureSources: [ContextSourceIdentity] = []
    private var exactCaptureCompletions: [(@MainActor (ContextSnapshot?) -> Void)] = []

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
    func captureExactPage(
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        exactCaptureCount += 1
        exactCaptureCompletions.append(completion)
    }

    func captureSourceIdentity() -> ContextSourceIdentity? {
        sourceIdentity
    }

    func captureExactPage(
        from source: ContextSourceIdentity,
        completion: @escaping @MainActor (ContextSnapshot?) -> Void
    ) {
        exactCaptureCount += 1
        exactCaptureSources.append(source)
        exactCaptureCompletions.append(completion)
    }
    func emit(_ snapshot: ContextSnapshot?) { onSnapshot?(snapshot) }
    func revokeAuthorization() {
        isAuthorized = false
        onAuthorizationChange?(false)
    }

    func completeExactCapture(
        at index: Int = 0,
        with snapshot: ContextSnapshot?
    ) {
        guard exactCaptureCompletions.indices.contains(index) else { return }
        let completion = exactCaptureCompletions.remove(at: index)
        completion(snapshot)
    }
}

@MainActor
private final class ContextSuggestionPreferencesSpy: ContextSuggestionPreferenceStoring {
    var isEnabled = false

    func load() -> Bool { isEnabled }
    func save(_ enabled: Bool) { isEnabled = enabled }
}

@MainActor
private final class ContextualActivePageBox {
    var pageID: String?

    init(pageID: String?) {
        self.pageID = pageID
    }

    func read() -> String? {
        pageID
    }
}

@MainActor
private final class ContextualActivationRecorder {
    private(set) var pages: [NotionPageReference] = []
    private(set) var restorations: [DurablePageRestoration?] = []

    func record(
        page: NotionPageReference,
        restoration: DurablePageRestoration?
    ) {
        pages.append(page)
        restorations.append(restoration)
    }
}
