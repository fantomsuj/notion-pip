import AppKit
@testable import Perch
import WebKit
import XCTest

final class PanelStashStateStoreTests: XCTestCase {
    func testMissingStateLaunchesVisible() throws {
        let defaults = try makeIsolatedDefaults()

        XCTAssertFalse(PanelStashStateStore(defaults: defaults).load())
    }

    func testSavedStashedStateSurvivesANewStore() throws {
        let defaults = try makeIsolatedDefaults()
        PanelStashStateStore(defaults: defaults).save(true)

        XCTAssertTrue(PanelStashStateStore(defaults: defaults).load())

        PanelStashStateStore(defaults: defaults).save(false)

        XCTAssertFalse(PanelStashStateStore(defaults: defaults).load())
    }
}

@MainActor
final class RuntimeQuietLaunchTests: XCTestCase {
    func testStashedAtQuitRestoresSavedPageStashedWithoutShowingIt() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let stashState = try PanelStashStateStore(defaults: makeIsolatedDefaults())
        stashState.save(true)
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            panelStashStateStore: stashState
        )
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntilRuntimeCondition { runtime.activePage?.pageID == firstPageID }

        XCTAssertEqual(panel.stashedRestorePages.map(\.pageID), [firstPageID])
        XCTAssertTrue(panel.shownPages.isEmpty)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(runtime.pipPresentationState, .stashed)
        XCTAssertEqual(runtime.lastActivationSource, .restored)
        XCTAssertTrue(stashState.load())
    }

    func testVisibleAtQuitRestoresSavedPageVisible() async throws {
        let panel = RuntimePanelCoordinator()
        let repository = RuntimePinnedPageRepository()
        let stashState = try PanelStashStateStore(defaults: makeIsolatedDefaults())
        stashState.save(false)
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            panelStashStateStore: stashState
        )
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntilRuntimeCondition { runtime.activePage?.pageID == firstPageID }

        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
        XCTAssertTrue(panel.stashedRestorePages.isEmpty)
        XCTAssertTrue(panel.isVisible)
    }

    func testStashingAndShowingThePanelSavesItsState() throws {
        let panel = RuntimePanelCoordinator()
        let stashState = try PanelStashStateStore(defaults: makeIsolatedDefaults())
        let runtime = makeRuntime(panel: panel, panelStashStateStore: stashState)
        let page = try makePage(id: firstPageID, title: "Roadmap")

        runtime.pin(page: page)
        XCTAssertFalse(stashState.load())

        runtime.handleMenuBarActivation()
        XCTAssertEqual(runtime.pipPresentationState, .stashed)
        XCTAssertTrue(stashState.load())

        runtime.handleMenuBarActivation()
        XCTAssertEqual(runtime.pipPresentationState, .visible)
        XCTAssertFalse(stashState.load())
    }

    func testLaunchWithACustomURLOpensOnlyTheCustomURL() async throws {
        let panel = RuntimePanelCoordinator()
        let customStore = try CustomPinnedURLStore(defaults: makeIsolatedDefaults())
        let pin = try CustomPinnedURL(validatingString: "https://canvas.example.edu")
        customStore.save(
            CustomPinnedURLSnapshot(isEnabled: true, pins: [pin], lastActiveID: pin.id)
        )
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            customPinnedURLStore: customStore
        )
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntilRuntimeCondition { runtime.activeCustomURL?.id == pin.id }

        XCTAssertEqual(panel.shownCustomURLs.map(\.id), [pin.id])
        XCTAssertTrue(panel.shownPages.isEmpty)
        XCTAssertTrue(panel.replacedPages.isEmpty)
        XCTAssertEqual(runtime.activePage?.pageID, firstPageID)

        runtime.returnToNotionPage()

        XCTAssertNil(runtime.activeCustomURL)
        XCTAssertEqual(panel.shownPages.map(\.pageID), [firstPageID])
    }

    func testStashedLaunchWithACustomURLRestoresOnlyTheCustomURLStashed() async throws {
        let panel = RuntimePanelCoordinator()
        let customStore = try CustomPinnedURLStore(defaults: makeIsolatedDefaults())
        let pin = try CustomPinnedURL(validatingString: "https://canvas.example.edu")
        customStore.save(
            CustomPinnedURLSnapshot(isEnabled: true, pins: [pin], lastActiveID: pin.id)
        )
        let stashState = try PanelStashStateStore(defaults: makeIsolatedDefaults())
        stashState.save(true)
        let repository = RuntimePinnedPageRepository()
        let runtime = makeRuntime(
            panel: panel,
            pageRepository: repository,
            customPinnedURLStore: customStore,
            panelStashStateStore: stashState
        )
        let storedPage = try makeStoredPage(id: firstPageID, title: "Roadmap")

        runtime.start()
        try await repository.waitUntilRestoreRequested()
        await repository.finishRestore(with: storedPage)
        await waitUntilRuntimeCondition { runtime.activeCustomURL?.id == pin.id }

        XCTAssertEqual(panel.stashedRestoreCustomURLs.map(\.id), [pin.id])
        XCTAssertTrue(panel.shownCustomURLs.isEmpty)
        XCTAssertTrue(panel.shownPages.isEmpty)
        XCTAssertTrue(panel.stashedRestorePages.isEmpty)
        XCTAssertEqual(runtime.pipPresentationState, .stashed)
    }
}

@MainActor
final class PiPPanelQuietLaunchTests: XCTestCase {
    func testStashedRestorePinsPageBehindTheHandleWithoutShowingOrLoadingIt() throws {
        let harness = makeHarness()
        let page = try makePage(id: firstPageID, title: "Roadmap")

        harness.coordinator.restoreStashed(page: page, restoration: nil)

        XCTAssertEqual(harness.coordinator.presentationState, .stashed)
        XCTAssertEqual(harness.coordinator.currentPage, page)
        XCTAssertFalse(harness.panel.isVisible)
        XCTAssertTrue(harness.handle.isVisible)
        // Hiding before activating keeps the web session from loading the page.
        XCTAssertEqual(harness.loader.events, ["hide", "activate:\(firstPageID)"])

        XCTAssertTrue(harness.coordinator.showCurrentPage())

        XCTAssertTrue(harness.panel.isVisible)
        XCTAssertEqual(harness.loader.events.last, "show")
    }

    func testStashedRestoreOfACustomURLDoesNotTouchTheNotionPage() throws {
        let harness = makeHarness()
        let pin = try CustomPinnedURL(validatingString: "https://canvas.example.edu")

        harness.coordinator.restoreStashed(customURL: pin)

        XCTAssertEqual(harness.coordinator.presentationState, .stashed)
        XCTAssertNil(harness.coordinator.currentPage)
        XCTAssertEqual(harness.coordinator.currentCustomURL?.id, pin.id)
        XCTAssertFalse(harness.panel.isVisible)
        XCTAssertEqual(harness.loader.events, ["hide", "activate-custom:\(pin.id)"])
    }

    func testStashedRestoreWithoutAHandleShowsThePanelInstead() throws {
        let panel = QuietLaunchPanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let loader = QuietLaunchPageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: nil,
            reducesMotion: { false },
            visibleFramesProvider: { [CGRect(x: 0, y: 0, width: 1_000, height: 800)] }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")

        coordinator.restoreStashed(page: page, restoration: nil)

        XCTAssertEqual(coordinator.presentationState, .visible)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(loader.events, ["activate:\(firstPageID)", "show"])
    }

    private func makeHarness() -> QuietLaunchHarness {
        let panel = QuietLaunchPanelWindow(frame: CGRect(x: 620, y: 100, width: 300, height: 400))
        let handle = QuietLaunchStashHandle()
        let loader = QuietLaunchPageLoader()
        let coordinator = PiPPanelCoordinator(
            panel: panel,
            pageLoader: loader,
            stashHandle: handle,
            reducesMotion: { false },
            visibleFramesProvider: { [CGRect(x: 0, y: 0, width: 1_000, height: 800)] }
        )
        return QuietLaunchHarness(
            coordinator: coordinator,
            panel: panel,
            handle: handle,
            loader: loader
        )
    }
}

// Lives on NotionWebSessionTests so CI runs it with the other WebKit suites.
extension NotionWebSessionTests {
    func testPageActivatedWhileHiddenBuildsNoWebViewUntilShown() throws {
        var createdWebViews: [WKWebView] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            webViewFactory: {
                let webView = WKWebView()
                createdWebViews.append(webView)
                return webView
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.panelDidHide()
        session.activate(page: page, restoration: nil)

        XCTAssertNil(session.webView)
        XCTAssertTrue(createdWebViews.isEmpty)

        session.panelDidShow()

        XCTAssertEqual(createdWebViews.count, 1)
        XCTAssertNotNil(session.webView)
    }
}

private func makeIsolatedDefaults() throws -> UserDefaults {
    let suiteName = "QuietLaunchTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw XCTSkip("Could not create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private struct QuietLaunchHarness {
    let coordinator: PiPPanelCoordinator
    let panel: QuietLaunchPanelWindow
    let handle: QuietLaunchStashHandle
    let loader: QuietLaunchPageLoader
}

@MainActor
private final class QuietLaunchPageLoader: NotionPageLoading {
    private(set) var events: [String] = []

    func activate(page: NotionPageReference) {
        events.append("activate:\(page.pageID)")
    }

    func activate(customURL: CustomPinnedURL) {
        events.append("activate-custom:\(customURL.id)")
    }

    func reloadPinnedPage(_ page: NotionPageReference) {}

    func panelDidShow() {
        events.append("show")
    }

    func panelDidHide() {
        events.append("hide")
    }
}

@MainActor
private final class QuietLaunchPanelWindow: PiPPanelWindow {
    private(set) var frame: CGRect
    private(set) var isVisible = false
    var isExpanded = false
    var isTrackpadMoveActive = false
    var onClose: (@MainActor () -> Void)?

    init(frame: CGRect = .zero) {
        self.frame = frame
    }

    func present() {
        isVisible = true
    }

    func orderOut() {
        isVisible = false
    }

    func restoreFromExpandedState() {}

    func setFrame(_ frame: CGRect, display: Bool) {
        self.frame = frame
    }

    func dismissForStash(
        toward placement: PanelStashPlacement,
        restoring restoreFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        setFrame(restoreFrame, display: false)
        orderOut()
        completion()
    }
}

@MainActor
private final class QuietLaunchStashHandle: PiPStashHandle {
    private(set) var isVisible = false

    func present(
        placement: PanelStashPlacement,
        onRestore: @escaping @MainActor () -> Void,
        onPlacementChange: @escaping @MainActor (PanelStashPlacement) -> Void,
        onPullRevealChange: @escaping @MainActor (CGFloat) -> Void,
        onPullRevealEnd: @escaping @MainActor (CGFloat) -> Bool
    ) {
        isVisible = true
    }

    func orderOut() {
        isVisible = false
    }
}
