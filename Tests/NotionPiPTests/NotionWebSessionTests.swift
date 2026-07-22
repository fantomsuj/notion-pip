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

    func testSelectingPinnedPageDoesNotCreateOrLoadWebView() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })

        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))

        XCTAssertEqual(session.activePage?.pageID, firstPageID)
        XCTAssertNil(session.webView)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(session.state, .unloaded)
    }

    func testSelectingLiveSurfaceCreatesAndLoadsSelectedPage() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)

        session.showLiveSurface()

        XCTAssertEqual(session.surface, .live)
        XCTAssertNotNil(session.webView)
        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
        XCTAssertEqual(session.state, .loading)
    }

    func testActivateDeduplicatesSamePageSelectionWithoutLoading() throws {
        let session = NotionWebSession()
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.activate(page: page)

        XCTAssertEqual(session.activePage?.pageID, firstPageID)
        XCTAssertEqual(session.state, .unloaded)
        XCTAssertNil(session.webView)
    }

    func testActivateReplacesTheActivePage() throws {
        let session = NotionWebSession()
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")

        session.activate(page: firstPage)
        session.activate(page: secondPage)

        XCTAssertEqual(session.activePage?.pageID, secondPageID)
        XCTAssertNil(session.webView)
    }

    func testNavigationDelegatePublishesReadyAndFailureStates() throws {
        let session = NotionWebSession()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        session.showLiveSurface()

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

    func testCreateNewPageLoadsFixedRouteOnceUntilNavigationCompletes() {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in
            requests.append(request)
        })

        session.createNewPage()
        session.createNewPage()

        XCTAssertEqual(requests.map(\.url?.absoluteString), ["https://www.notion.so/new"])
        XCTAssertTrue(session.isCreatingNewPage)
        XCTAssertEqual(session.state, .loading)
    }

    func testHiddenCreateNewPageWaitsForShowAndReusesWarmWebViewOnce() throws {
        var requests: [URLRequest] = []
        var creationCount = 0
        var eviction: (@MainActor () -> Void)?
        var evictionCancellationCount = 0
        let session = NotionWebSession(
            loadRequest: { _, request in requests.append(request) },
            webViewFactory: {
                creationCount += 1
                return WKWebView()
            },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable { evictionCancellationCount += 1 }
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let warmWebView = try XCTUnwrap(session.webView)
        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
        XCTAssertEqual(creationCount, 1)

        session.panelDidHide()

        XCTAssertEqual(session.state, .suspended)
        XCTAssertFalse(session.shouldHostWebView)

        session.createNewPage()
        session.createNewPage()

        XCTAssertEqual(requests.map(\.url), [page.canonicalURL])
        XCTAssertEqual(creationCount, 1)
        XCTAssertTrue(session.webView === warmWebView)
        XCTAssertEqual(session.state, .suspended)
        XCTAssertFalse(session.shouldHostWebView)
        XCTAssertTrue(session.isCreatingNewPage)

        session.panelDidShow()

        XCTAssertEqual(requests.map(\.url), [page.canonicalURL, NotionWebSession.newPageURL])
        XCTAssertEqual(creationCount, 1)
        XCTAssertTrue(session.webView === warmWebView)
        XCTAssertEqual(session.state, .loading)
        XCTAssertTrue(session.shouldHostWebView)
        XCTAssertEqual(evictionCancellationCount, 1)

        eviction?()

        XCTAssertEqual(requests.map(\.url), [page.canonicalURL, NotionWebSession.newPageURL])
        XCTAssertTrue(session.webView === warmWebView)
        XCTAssertEqual(session.state, .loading)
        XCTAssertTrue(session.shouldHostWebView)
    }

    func testLiveOnlyCreationUsesPersistentStoreAndSuspendsInactiveScheduling() throws {
        let session = NotionWebSession(loadRequest: { _, _ in })

        session.createNewPage()

        let configuration = try XCTUnwrap(session.webView).configuration
        XCTAssertTrue(configuration.websiteDataStore === WKWebsiteDataStore.default())
        XCTAssertEqual(configuration.preferences.inactiveSchedulingPolicy, .suspend)
    }

    func testPreviewImmediatelyEndsEditingPausesDetachesAndSchedulesSixtySecondWarmPeriod() throws {
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
        session.showLiveSurface()
        let webView = try XCTUnwrap(session.webView)
        let container = NSView()
        container.addSubview(webView)
        session.handleEditorActivity(.typingStarted)

        session.showPreviewSurface()

        XCTAssertEqual(session.surface, .preview)
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
        session.showLiveSurface()
        let webView = try XCTUnwrap(session.webView)
        session.showPreviewSurface()

        eviction?()

        XCTAssertNil(session.webView)
        XCTAssertEqual(session.state, .unloaded)
        XCTAssertEqual(stoppedWebViews, [webView])
        XCTAssertNil(webView.navigationDelegate)
        XCTAssertTrue(webView.configuration.userContentController.userScripts.isEmpty)
    }

    func testMemoryPressureEvictsOnlyHiddenNonTypingWarmWebView() throws {
        var stoppedWebViews: [WKWebView] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            stopLoading: { stoppedWebViews.append($0) }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.showLiveSurface()
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

    func testEvictedLiveSurfaceRecreatesAndRestoresInteractionState() throws {
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
        session.showLiveSurface()
        session.showPreviewSurface()
        eviction?()

        session.showLiveSurface()

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
        session.showLiveSurface()
        session.showPreviewSurface()

        session.activate(page: secondPage)
        eviction?()
        session.showLiveSurface()

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
        session.showLiveSurface()
        session.showPreviewSurface()

        session.activate(page: secondPage)
        eviction?()
        session.showLiveSurface()

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
        session.showLiveSurface()
        session.showPreviewSurface()
        session.activate(page: secondPage)

        session.adoptResolvedPage(at: firstPage.canonicalURL)

        XCTAssertEqual(session.activePage, secondPage)
        XCTAssertTrue(resolvedPages.isEmpty)
    }

    func testPostResumeStaleCandidateCannotReplaceOwnedCurrentWebViewURL() throws {
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
        session.showLiveSurface()
        session.panelDidHide()
        session.activate(page: secondPage)

        session.panelDidShow()
        XCTAssertEqual(webView.url, secondPage.canonicalURL)
        session.adoptResolvedPage(at: firstPage.canonicalURL)

        XCTAssertEqual(session.activePage, secondPage)
        XCTAssertTrue(resolvedPages.isEmpty)
    }

    func testExplicitSelectionCancelsSuspendedNewPageResolutionAuthority() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        let selectedPage = try makePage(id: secondPageID, title: "Notes")
        let pendingNewPage = try makePage(id: firstPageID, title: "Created")
        session.onPageResolved = { resolvedPages.append($0) }
        session.createNewPage()
        session.showPreviewSurface()

        session.activate(page: selectedPage)
        session.adoptResolvedPage(at: pendingNewPage.canonicalURL)

        XCTAssertFalse(session.isCreatingNewPage)
        XCTAssertEqual(session.activePage, selectedPage)
        XCTAssertTrue(resolvedPages.isEmpty)
    }

    func testReselectingSameActivePageCancelsPendingNewPageAndRestoresCanonicalURL() throws {
        var requests: [URLRequest] = []
        var resolvedPages: [NotionPageReference] = []
        let webView = WKWebView()
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { webView, request in
                requests.append(request)
                webView.load(request)
            }
        )
        let activePage = try makePage(id: firstPageID, title: "Roadmap")
        let pendingNewPage = try makePage(id: secondPageID, title: "Created")
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: activePage)
        session.showLiveSurface()
        session.createNewPage()

        session.reselect(page: activePage)

        XCTAssertFalse(session.isCreatingNewPage)
        XCTAssertEqual(webView.url, activePage.canonicalURL)
        XCTAssertEqual(requests.map(\.url), [
            activePage.canonicalURL,
            NotionWebSession.newPageURL,
            activePage.canonicalURL,
        ])
        session.adoptResolvedPage(at: pendingNewPage.canonicalURL)
        XCTAssertEqual(session.activePage, activePage)
        XCTAssertTrue(resolvedPages.isEmpty)
    }

    func testFinishedNewPageNavigationAdoptsResolvedPageBeforeClearingAuthority() throws {
        var resolvedPages: [NotionPageReference] = []
        let resolvedPage = try makePage(id: firstPageID, title: "Created")
        let webView = WKWebView()
        webView.load(URLRequest(url: resolvedPage.canonicalURL))
        XCTAssertEqual(webView.url, resolvedPage.canonicalURL)
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in }
        )
        session.onPageResolved = { resolvedPages.append($0) }
        session.createNewPage()
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        navigationDelegate.webView?(webView, didFinish: nil)

        XCTAssertEqual(session.activePage, resolvedPage)
        XCTAssertEqual(resolvedPages, [resolvedPage])
        XCTAssertFalse(session.isCreatingNewPage)
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
        session.showLiveSurface()
        session.showPreviewSurface()
        eviction?()

        session.showLiveSurface()

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
        session.showLiveSurface()
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
        session.showLiveSurface()
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
        session.showLiveSurface()
        let chrome = PiPChromeView(
            webSession: session,
            nativePageDocument: NativePageDocument()
        )
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
        session.showLiveSurface()
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
        session.showLiveSurface()
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
        session.showLiveSurface()
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
        session.showLiveSurface()
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

    func testFailedCreationAllowsAnotherAttempt() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in
            requests.append(request)
        })
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        session.createNewPage()
        let webView = try XCTUnwrap(session.webView)

        navigationDelegate.webView?(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "Test", code: 1)
        )
        session.createNewPage()

        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(session.isCreatingNewPage)
    }

    func testURLChangeReportsNewCanonicalPageOnceAcrossNavigationCompletion() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        session.showLiveSurface()
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
        XCTAssertFalse(session.isCreatingNewPage)
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

    func testFinishedAppHostNewPageNavigationResolvesBeforeClearingCreationState() throws {
        var resolvedPages: [NotionPageReference] = []
        let resolvedURL = try XCTUnwrap(
            URL(string: "https://app.notion.com/Created-\(firstPageID)?pvs=4")
        )
        let webView = WKWebView()
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { webView, request in webView.load(request) }
        )
        session.onPageResolved = { resolvedPages.append($0) }
        session.createNewPage()
        webView.load(URLRequest(url: resolvedURL))
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)

        navigationDelegate.webView?(webView, didFinish: nil)

        XCTAssertEqual(session.activePage?.canonicalURL.absoluteString, "https://app.notion.com/Created-\(firstPageID)")
        XCTAssertEqual(resolvedPages.map(\.pageID), [firstPageID])
        XCTAssertFalse(session.isCreatingNewPage)
    }

    func testFinishedIntermediateNavigationDoesNotReplaceActivePage() throws {
        var resolvedPages: [NotionPageReference] = []
        let session = NotionWebSession()
        let original = try makePage(id: firstPageID, title: "Roadmap")
        session.onPageResolved = { resolvedPages.append($0) }
        session.activate(page: original)
        session.showLiveSurface()
        let webView = try XCTUnwrap(session.webView)
        webView.load(
            URLRequest(url: try XCTUnwrap(URL(string: "https://www.notion.so/new")))
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

    func testTypingActivityHidesTopControlsUntilEditingEnds() {
        let session = NotionWebSession()
        let chrome = PiPChromeView(
            webSession: session,
            nativePageDocument: NativePageDocument()
        )

        XCTAssertFalse(session.isTypingInPage)
        XCTAssertTrue(chrome.showsTopControls)

        session.handleEditorActivity(.typingStarted)

        XCTAssertTrue(session.isTypingInPage)
        XCTAssertFalse(chrome.showsTopControls)

        session.handleEditorActivity(.editingEnded)

        XCTAssertFalse(session.isTypingInPage)
        XCTAssertTrue(chrome.showsTopControls)
    }

    func testVoiceOverKeepsTopControlsVisibleWhileTyping() {
        XCTAssertFalse(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: true,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: true,
                isFullKeyboardAccessEnabled: false
            )
        )
        XCTAssertTrue(
            PiPChromeView.shouldShowTopControls(
                isTypingInPage: true,
                isVoiceOverEnabled: false,
                isSwitchControlEnabled: false,
                isFullKeyboardAccessEnabled: true
            )
        )
    }

    func testEditorActivityScriptRunsAtDocumentStartInMainFrameOnly() throws {
        let session = NotionWebSession()
        session.createNewPage()
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
        session.createNewPage()
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
        session.showLiveSurface()
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
        session.createNewPage()
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
        let chrome = PiPChromeView(
            webSession: session,
            nativePageDocument: NativePageDocument()
        )
        let presentation = String(reflecting: chrome.body)

        XCTAssertTrue(presentation.contains("Notion couldn't load this page."))
        XCTAssertTrue(presentation.contains("Try Again"))
        XCTAssertFalse(presentation.contains("secret"))
    }

    func testPiPChromeExposesAccessibleToolbarActionsWithoutRedundantHideAction() {
        let chrome = PiPChromeView(
            webSession: NotionWebSession(),
            nativePageDocument: NativePageDocument(),
            onStash: {}
        )

        _ = chrome.body

        XCTAssertEqual(PiPChromeView.newPageAccessibilityLabel, "Create New Notion Page")
        XCTAssertEqual(PiPChromeView.newPageHelp, "Create a new page in Notion")
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
