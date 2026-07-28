import AppKit
import Combine
import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class NotionWebSessionTests: XCTestCase {
    private let firstPageID = "0123456789abcdef0123456789abcdef"
    private let secondPageID = "fedcba9876543210fedcba9876543210"

    func testSessionStartsUnloadedWithoutCreatingWebView() {
        let session = NotionWebSession()

        XCTAssertNil(session.webView)
        XCTAssertEqual(session.state, .unloaded)
    }

    func testSelectingPinnedPageCreatesAndLoadsLiveWebView() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)

        XCTAssertEqual(session.activePage?.pageID, firstPageID)
        XCTAssertNotNil(session.webView)
        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
        XCTAssertEqual(session.state, .loading)
    }

    func testActivateDeduplicatesSamePageSelectionWithoutReloading() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.activate(page: page)

        XCTAssertEqual(session.activePage?.pageID, firstPageID)
        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
        XCTAssertEqual(session.state, .loading)
        XCTAssertNotNil(session.webView)
    }

    func testActivateReplacesTheActivePage() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        session.activate(page: firstPage)
        session.activate(page: secondPage)

        XCTAssertEqual(session.activePage?.pageID, secondPageID)
        XCTAssertEqual(requests.map(\.url), [firstPage.canonicalURL, secondPage.canonicalURL])
        XCTAssertNotNil(session.webView)
    }

    func testPageSwitchCapturesOutgoingStateTearsDownViewAndRestoresItOnReturn() throws {
        var createdWebViews: [WKWebView] = []
        var stoppedWebViews: [WKWebView] = []
        var endedEditing: [WKWebView] = []
        var restoredStates: [String] = []
        var capturedRestorations: [DurablePageRestoration] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            webViewFactory: {
                let webView = WKWebView()
                createdWebViews.append(webView)
                return webView
            },
            stopLoading: { stoppedWebViews.append($0) },
            interactionStateReader: { webView in
                createdWebViews.firstIndex(where: { $0 === webView }) == 0
                    ? "first-state"
                    : "second-state"
            },
            interactionStateWriter: { _, state in
                if let state = state as? String {
                    restoredStates.append(state)
                }
            },
            endEditing: { endedEditing.append($0) }
        )
        session.onRestorationCaptured = { capturedRestorations.append($0) }
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")

        session.activate(page: first)
        let firstWebView = try XCTUnwrap(session.webView)
        session.activate(page: second)
        let secondWebView = try XCTUnwrap(session.webView)
        session.activate(page: first)

        XCTAssertFalse(firstWebView === secondWebView)
        XCTAssertFalse(secondWebView === session.webView)
        XCTAssertEqual(createdWebViews.count, 3)
        XCTAssertEqual(stoppedWebViews, [firstWebView, secondWebView])
        XCTAssertEqual(endedEditing, [firstWebView, secondWebView])
        XCTAssertEqual(restoredStates, ["first-state"])
        XCTAssertEqual(capturedRestorations.map(\.pageID), [firstPageID, secondPageID])
    }

    func testDurableRestorationLoadsValidatedLastURLAndAppliesScrollAfterFinish() throws {
        var requests: [URLRequest] = []
        var appliedRestorations: [DurablePageRestoration] = []
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let lastURL = try XCTUnwrap(
            URL(string: "\(page.canonicalURL.absoluteString)?pvs=4")
        )
        let restoration = try DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: lastURL,
            scrollX: 3,
            scrollY: 400,
            scrollProgress: 0.6,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            scrollRestorer: { _, restoration in
                appliedRestorations.append(restoration)
            }
        )

        session.activate(page: page, restoration: restoration)
        let webView = try XCTUnwrap(session.webView)
        session.webView(webView, didFinish: nil)

        XCTAssertEqual(requests.map(\.url), [lastURL])
        XCTAssertEqual(appliedRestorations, [restoration])
    }

    func testFailedDurableURLFallsBackToCanonicalPageOnlyOnce() throws {
        var requests: [URLRequest] = []
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let savedURL = try XCTUnwrap(
            URL(string: "\(page.canonicalURL.absoluteString)?pvs=4")
        )
        let restoration = try DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: savedURL,
            scrollX: 0,
            scrollY: 100,
            scrollProgress: 0.2,
            updatedAt: Date()
        )
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) }
        )
        session.activate(page: page, restoration: restoration)
        let webView = try XCTUnwrap(session.webView)
        let error = NSError(domain: "Test", code: 1)

        session.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        session.webView(webView, didFailProvisionalNavigation: nil, withError: error)

        XCTAssertEqual(requests.map(\.url), [savedURL, page.canonicalURL])
        guard case .failed = session.state else {
            return XCTFail("Expected the canonical fallback failure to be published")
        }
    }

    func testInteractionSnapshotEvictionKeepsDurableFallback() throws {
        var requests: [URLRequest] = []
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            interactionStateReader: { _ in "opaque" }
        )

        session.activate(page: first)
        session.activate(page: second)
        session.evictInteractionSnapshots(retaining: [])
        session.activate(page: first)

        XCTAssertEqual(requests.last?.url, first.canonicalURL)
    }

    func testScrollBridgeAcceptsOnlyStrictMainFrameNotionMessages() {
        let body: [String: Any] = [
            "x": 4.0,
            "y": 120.0,
            "progress": 0.5,
        ]

        XCTAssertEqual(
            NotionScrollBridge.snapshot(
                from: body,
                isMainFrame: true,
                scheme: "https",
                host: "app.notion.com"
            ),
            NotionScrollSnapshot(x: 4, y: 120, progress: 0.5)
        )
        XCTAssertNil(
            NotionScrollBridge.snapshot(
                from: body,
                isMainFrame: false,
                scheme: "https",
                host: "app.notion.com"
            )
        )
        XCTAssertNil(
            NotionScrollBridge.snapshot(
                from: body,
                isMainFrame: true,
                scheme: "https",
                host: "notion.example.com"
            )
        )
        XCTAssertNil(
            NotionScrollBridge.snapshot(
                from: ["x": 0, "y": 1, "progress": 2],
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
    }

    func testNavigationDelegatePublishesReadyAndFailureStates() throws {
        let session = NotionWebSession()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)

        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        let webView = try XCTUnwrap(session.webView)
        navigationDelegate.webView?(webView, didFinish: nil)
        XCTAssertEqual(session.state, .active)

        navigationDelegate.webView?(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline"])
        )
        XCTAssertEqual(session.state, .failed("Offline"))
    }

    func testOpenInBrowserUsesTheActivePageURL() throws {
        var openedURLs: [URL] = []
        let session = NotionWebSession(openURL: { openedURLs.append($0) })
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.openInBrowser()

        XCTAssertEqual(openedURLs, [page.canonicalURL])
    }

    func testLivePageUsesPersistentStoreAndSuspendsInactiveScheduling() throws {
        let session = NotionWebSession(loadRequest: { _, _ in })

        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))

        let configuration = try XCTUnwrap(session.webView).configuration
        XCTAssertTrue(configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertEqual(configuration.preferences.inactiveSchedulingPolicy, .suspend)
    }

    func testHidingPanelEndsEditingPausesDetachesAndSchedulesSixtySecondWarmPeriod() throws {
        var scheduledInterval: TimeInterval?
        var pausedWebViews: [WKWebView] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { interval, _ in
                scheduledInterval = interval
                return AnyCancellable {}
            },
            pauseMedia: { pausedWebViews.append($0) }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let container = NSView()
        container.addSubview(webView)
        session.handleEditorActivity(.typingStarted)

        session.panelDidHide()

        XCTAssertEqual(session.state, .suspended)
        XCTAssertFalse(session.isTypingInPage)
        XCTAssertNil(webView.superview)
        XCTAssertEqual(pausedWebViews, [webView])
        XCTAssertEqual(scheduledInterval, 60)
        XCTAssertTrue(session.webView === webView)
    }

    func testWarmPeriodEvictsAndCleansUpSuspendedWebView() throws {
        var eviction: (@MainActor () -> Void)?
        var stoppedWebViews: [WKWebView] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            stopLoading: { stoppedWebViews.append($0) }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        session.panelDidHide()

        eviction?()

        XCTAssertNil(session.webView)
        XCTAssertEqual(session.state, .unloaded)
        XCTAssertEqual(stoppedWebViews, [webView])
        XCTAssertNil(webView.navigationDelegate)
        XCTAssertNil(webView.uiDelegate)
        XCTAssertTrue(webView.configuration.userContentController.userScripts.isEmpty)
    }

    func testConfiguredWebViewUsesSessionForNavigationAndUIRequests() throws {
        let webView = WKWebView()
        let session = NotionWebSession(webView: webView)

        XCTAssertTrue(webView.navigationDelegate === session)
        XCTAssertTrue(webView.uiDelegate === session)
        XCTAssertNotNil(session as WKUIDelegate)
    }

    func testMemoryPressureEvictsOnlyHiddenNonTypingWarmWebView() throws {
        var stoppedWebViews: [WKWebView] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            stopLoading: { stoppedWebViews.append($0) }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)

        session.handleMemoryPressure()
        XCTAssertTrue(session.webView === webView)

        session.panelDidHide()
        session.handleEditorActivity(.typingStarted)
        session.handleMemoryPressure()
        XCTAssertTrue(session.webView === webView)

        session.handleEditorActivity(.editingEnded)
        session.handleMemoryPressure()
        XCTAssertNil(session.webView)
        XCTAssertEqual(stoppedWebViews, [webView])
    }

    func testShowingPanelAfterEvictionRecreatesAndRestoresInteractionState() throws {
        var eviction: (@MainActor () -> Void)?
        var requests: [URLRequest] = []
        var restoredStates: [String] = []
        var creationCount = 0
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            webViewFactory: {
                creationCount += 1
                return WKWebView()
            },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            interactionStateReader: { _ in "saved-interaction" },
            interactionStateWriter: { _, state in
                if let state = state as? String {
                    restoredStates.append(state)
                }
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        session.panelDidHide()
        eviction?()
        session.panelDidShow()
        session.panelDidShow()

        XCTAssertEqual(creationCount, 2)
        XCTAssertEqual(restoredStates, ["saved-interaction"])
        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
        XCTAssertEqual(session.state, .loading)
    }

    func testChangingSelectedPageWhileSuspendedDiscardsStaleStateAndLoadsNewPage() throws {
        var eviction: (@MainActor () -> Void)?
        var requests: [URLRequest] = []
        var restoredStateCount = 0
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            interactionStateReader: { _ in "stale-interaction" },
            interactionStateWriter: { _, _ in restoredStateCount += 1 }
        )
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        session.activate(page: firstPage)
        session.panelDidHide()

        session.activate(page: secondPage)
        eviction?()
        session.panelDidShow()

        XCTAssertEqual(requests.map(\.url), [firstPage.canonicalURL, secondPage.canonicalURL])
        XCTAssertEqual(restoredStateCount, 0)
        XCTAssertEqual(session.activePage, secondPage)
    }

    func testEvictionAfterSuspendedPageChangeDoesNotRestoreOldWebViewURL() throws {
        var eviction: (@MainActor () -> Void)?
        var requests: [URLRequest] = []
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        let oldWebView = WKWebView()
        oldWebView.load(URLRequest(url: firstPage.canonicalURL))
        XCTAssertEqual(oldWebView.url, firstPage.canonicalURL)
        let session = NotionWebSession(
            webView: oldWebView,
            loadRequest: { _, request in requests.append(request) },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            interactionStateReader: { _ in nil }
        )
        session.activate(page: firstPage)
        session.panelDidHide()

        session.activate(page: secondPage)
        eviction?()
        session.panelDidShow()

        XCTAssertEqual(requests.map(\.url), [firstPage.canonicalURL, secondPage.canonicalURL])
    }

    func testLateOldPageResolutionCannotReplaceNewSelectionWhileSuspended() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: firstPage)
        session.panelDidHide()
        session.activate(page: secondPage)

        session.adoptResolvedPage(at: firstPage.canonicalURL)

        XCTAssertEqual(session.activePage, secondPage)
        XCTAssertTrue(resolvedPages.isEmpty)
    }

    func testPostResumeStaleCandidateCannotReplaceReplacementWebViewURL() throws {
        var resolvedPages: [NotionPageReference] = []
        let webView = WKWebView()
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { webView, request in webView.load(request) },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: firstPage)
        session.panelDidHide()
        session.activate(page: secondPage)

        session.panelDidShow()
        let replacementWebView = try XCTUnwrap(session.webView)
        XCTAssertFalse(replacementWebView === webView)
        XCTAssertEqual(replacementWebView.url, secondPage.canonicalURL)
        session.adoptResolvedPage(at: firstPage.canonicalURL)

        XCTAssertEqual(session.activePage, secondPage)
        XCTAssertTrue(resolvedPages.isEmpty)
    }

    func testEvictionWithoutInteractionStateReloadsSavedCanonicalURL() throws {
        var eviction: (@MainActor () -> Void)?
        var requests: [URLRequest] = []
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            interactionStateReader: { _ in nil }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        session.panelDidHide()
        eviction?()
        session.panelDidShow()

        XCTAssertEqual(requests.map(\.url), [page.canonicalURL, page.canonicalURL])
    }

    func testLifecyclePublishesUnloadedLoadingActiveSuspendedUnloaded() throws {
        var eviction: (@MainActor () -> Void)?
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        XCTAssertEqual(session.state, .unloaded)

        session.activate(page: page)
        XCTAssertEqual(session.state, .loading)

        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(try XCTUnwrap(session.webView), didFinish: nil)
        XCTAssertEqual(session.state, .active)

        session.panelDidHide()
        XCTAssertEqual(session.state, .suspended)

        eviction?()
        XCTAssertEqual(session.state, .unloaded)
    }

    func testPanelVisibilityChangesPublishWhileSessionRemainsUnloaded() {
        let session = NotionWebSession()
        var publicationCount = 0
        let observation = session.objectWillChange.sink {
            publicationCount += 1
        }

        session.panelDidHide()
        session.panelDidShow()

        XCTAssertEqual(session.state, .unloaded)
        XCTAssertNil(session.webView)
        XCTAssertEqual(publicationCount, 2)
        withExtendedLifetime(observation) {}
    }

    func testShowingPanelResumesWarmLiveWebViewWithoutReloading() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)
        session.panelDidHide()

        session.panelDidShow()

        XCTAssertTrue(session.webView === webView)
        XCTAssertEqual(session.state, .active)
        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
    }

    func testLiveWebViewHostingStopsWhileSuspendedAndReturnsAfterPanelShow() throws {
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let chrome = PiPChromeView(webSession: session)
        XCTAssertTrue(session.shouldHostWebView)
        XCTAssertTrue(PiPChromeView.shouldHostNotionWebView(for: session))

        session.panelDidHide()

        XCTAssertFalse(session.shouldHostWebView)
        XCTAssertFalse(PiPChromeView.shouldHostNotionWebView(for: session))
        session.panelDidShow()
        XCTAssertTrue(session.shouldHostWebView)
        XCTAssertTrue(PiPChromeView.shouldHostNotionWebView(for: session))
        _ = chrome.body
    }

    func testHiddenNavigationStartRemainsSuspendedAndOriginalTimerCanEvict() throws {
        var eviction: (@MainActor () -> Void)?
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.panelDidHide()

        navigationDelegate.webView?(webView, didStartProvisionalNavigation: nil)

        XCTAssertEqual(session.state, .suspended)
        eviction?()
        XCTAssertNil(session.webView)
    }

    func testHiddenNavigationFinishRemainsSuspendedAndOriginalTimerCanEvict() throws {
        var eviction: (@MainActor () -> Void)?
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.panelDidHide()

        navigationDelegate.webView?(webView, didFinish: nil)

        XCTAssertEqual(session.state, .suspended)
        eviction?()
        XCTAssertNil(session.webView)
    }

    func testHiddenNavigationFailureRemainsSuspendedAndOriginalTimerCanEvict() throws {
        var eviction: (@MainActor () -> Void)?
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.panelDidHide()
        let error = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Offline"]
        )

        navigationDelegate.webView?(webView, didFail: nil, withError: error)

        XCTAssertEqual(session.state, .suspended)
        eviction?()
        XCTAssertNil(session.webView)
    }

    func testHiddenNavigationOutcomesBecomeVisibleOnlyAfterPanelResumes() throws {
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        session.panelDidHide()
        navigationDelegate.webView?(webView, didFinish: nil)
        XCTAssertEqual(session.state, .suspended)
        session.panelDidShow()
        XCTAssertEqual(session.state, .active)

        session.panelDidHide()
        navigationDelegate.webView?(
            webView,
            didFail: nil,
            withError: NSError(
                domain: "Test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Offline"]
            )
        )
        XCTAssertEqual(session.state, .suspended)
        session.panelDidShow()
        XCTAssertEqual(session.state, .failed("Offline"))

        session.panelDidHide()
        navigationDelegate.webView?(webView, didStartProvisionalNavigation: nil)
        XCTAssertEqual(session.state, .suspended)
        session.panelDidShow()
        XCTAssertEqual(session.state, .loading)
    }

    func testURLChangeReportsNewCanonicalPageOnceAcrossNavigationCompletion() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        webView.load(
            URLRequest(
                url: try XCTUnwrap(
                    URL(string: "https://www.notion.so/New-Page-\(secondPageID)?pvs=4")
                )
            )
        )
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        XCTAssertEqual(resolvedPages.map(\.pageID), [secondPageID])
        XCTAssertEqual(session.activePage?.pageID, secondPageID)

        navigationDelegate.webView?(webView, didFinish: nil)
        navigationDelegate.webView?(webView, didFinish: nil)

        XCTAssertEqual(resolvedPages.map(\.pageID), [secondPageID])
        XCTAssertEqual(session.activePage?.pageID, secondPageID)
    }

    func testAppHostSPAURLChangeAdoptsCanonicalPage() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let resolvedURL = try XCTUnwrap(
            URL(string: "https://app.notion.com/New-Page-\(secondPageID)?pvs=4#focus")
        )

        webView.load(URLRequest(url: resolvedURL))

        XCTAssertEqual(resolvedPages.map(\.canonicalURL.absoluteString), [
            "https://app.notion.com/New-Page-\(secondPageID)",
        ])
        XCTAssertEqual(session.activePage?.pageID, secondPageID)
    }

    func testFinishedIntermediateNavigationDoesNotReplaceActivePage() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        let original = try makePage(id: firstPageID, title: "Roadmap")
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: original)
        let webView = try XCTUnwrap(session.webView)
        webView.load(
            URLRequest(url: try XCTUnwrap(URL(string: "https://www.notion.so/")))
        )
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        navigationDelegate.webView?(webView, didFinish: nil)

        XCTAssertTrue(resolvedPages.isEmpty)
        XCTAssertEqual(session.activePage, original)
    }

    func testEditorActivityBridgeAcceptsOnlyMainFrameNotionHTTPSMessages() {
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "https",
                host: "app.notion.com"
            ),
            .typingStarted
        )
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            ),
            .typingStarted
        )
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "editingEnded",
                isMainFrame: true,
                scheme: "https",
                host: "notion.so"
            ),
            .editingEnded
        )

        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: false,
                scheme: "https",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "http",
                host: "www.notion.so"
            )
        )
        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: "typingStarted",
                isMainFrame: true,
                scheme: "https",
                host: "notion.example"
            )
        )
        XCTAssertNil(
            NotionEditorActivityBridge.activity(
                from: ["activity": "typingStarted"],
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
            )
        )
    }

    func testPiPChromeDoesNotRepeatWindowBrandIconInsideContent() {
        let chrome = PiPChromeView(webSession: NotionWebSession())

        XCTAssertFalse(String(reflecting: chrome.body).contains("rectangle.on.rectangle"))
    }

    func testPiPChromeOmitsPageSurfaceControlsFromTopBar() {
        let chrome = PiPChromeView(webSession: NotionWebSession())

        XCTAssertFalse(String(reflecting: chrome.body).contains("Page surface"))
    }

    func testTopControlsAreHiddenUntilTopEdgeIsHovered() {
        XCTAssertFalse(
            PiPChromeView.shouldShowTopControls(
                isHoveringTopEdge: false,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isHoveringTopEdge: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
    }

    func testHiddenTopControlsReserveNoLayoutHeight() {
        XCTAssertEqual(PiPChromeView.topControlsReservedHeight(isVisible: false), 0)
        XCTAssertEqual(
            PiPChromeView.topControlsReservedHeight(isVisible: true),
            PiPChromeView.topControlsHeight
        )
    }

    func testAccessibilityFeaturesKeepTopControlsVisibleWithoutHover() {
        XCTAssertFalse(
            PiPChromeView.shouldShowTopControls(
                isHoveringTopEdge: false,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isHoveringTopEdge: false,
                isVoiceOverEnabled: true,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isHoveringTopEdge: false,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: true,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isHoveringTopEdge: false,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: true
            )
        )
    }

    func testEditorActivityScriptRunsAtDocumentStartInMainFrameOnly() throws {
        let session = NotionWebSession()
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        let script = try XCTUnwrap(
            webView.configuration.userContentController.userScripts.first
        )

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertTrue(script.isForMainFrameOnly)
        XCTAssertTrue(script.source.contains("beforeinput"))
        XCTAssertTrue(script.source.contains("pointermove"))
        XCTAssertTrue(script.source.contains("focusout"))
        XCTAssertTrue(
            script.source.contains(
                "if (editableElement(event.target)) publishTypingStarted();"
            )
        )
    }

    func testNavigationResetsTypingActivity() throws {
        let session = NotionWebSession()
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.handleEditorActivity(.typingStarted)

        navigationDelegate.webView?(
            try XCTUnwrap(session.webView),
            didStartProvisionalNavigation: nil
        )

        XCTAssertFalse(session.isTypingInPage)
    }

    func testAdoptingResolvedSPAPageResetsTypingActivity() throws {
        let session = NotionWebSession()
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.handleEditorActivity(.typingStarted)
        let webView = try XCTUnwrap(session.webView)
        webView.load(
            URLRequest(
                url: try XCTUnwrap(
                    URL(string: "https://www.notion.so/Notes-\(secondPageID)")
                )
            )
        )

        XCTAssertFalse(session.isTypingInPage)
        XCTAssertEqual(session.activePage?.pageID, secondPageID)
    }

    func testFailureStateShowsGenericMessageAndRetryWithoutExposingWebKitErrorText() throws {
        let session = NotionWebSession()
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(
            try XCTUnwrap(session.webView),
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: "Test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Request to https://www.notion.so/?token=secret failed"]
            )
        )
        let chrome = PiPChromeView(webSession: session)
        let presentation = String(reflecting: chrome.body)

        XCTAssertTrue(presentation.contains("Notion couldn't load this page."))
        XCTAssertTrue(presentation.contains("Try Again"))
        XCTAssertFalse(presentation.contains("secret"))
    }

    func testPiPChromeExposesAccessibleToolbarActionsWithoutRedundantHideAction() {
        let chrome = PiPChromeView(
            webSession: NotionWebSession(),
            onStash: {}
        )

        _ = chrome.body

        XCTAssertEqual(PiPChromeView.primaryActionAccessibilityLabel, "Quick Capture")
        XCTAssertEqual(PiPChromeView.primaryActionHelp, "Capture a note for Notion")
        XCTAssertEqual(PiPChromeView.stashAccessibilityLabel, "Stash Notion PiP to Side")
        XCTAssertEqual(
            PiPChromeView.stashHelp,
            "Move the Notion PiP to the nearest screen edge"
        )
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }
}
