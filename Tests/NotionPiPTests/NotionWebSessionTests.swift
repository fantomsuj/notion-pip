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

    func testInteractionStateCacheCapsEntriesAndRefreshesUpdatedKeys() {
        var cache = NotionInteractionStateCache(capacity: 2)
        cache.insert("first-state", forKey: "first")
        cache.insert("second-state", forKey: "second")
        cache.insert("first-newer-state", forKey: "first")
        cache.insert("third-state", forKey: "third")

        XCTAssertNil(cache.takeValue(forKey: "second"))
        XCTAssertEqual(cache.takeValue(forKey: "first") as? String, "first-newer-state")
        XCTAssertEqual(cache.takeValue(forKey: "third") as? String, "third-state")
        XCTAssertEqual(cache.count, 0)
    }

    func testSessionMeasuresRestorationAndWebViewEvictionWithCacheCount() throws {
        let signposter = PerformanceSignposterSpy()
        let documentID = UUID()
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            interactionStateReader: { _ in "saved" },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(documentID)
            },
            performanceSignposter: signposter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)

        session.webView(webView, didCommit: nil)
        session.webView(webView, didFinish: nil)
        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: documentID),
            from: webView,
            generation: 1
        )
        session.panelDidHide()
        session.handleMemoryPressure()

        XCTAssertTrue(signposter.beginCalls.contains(.notionSessionRestoration))
        XCTAssertTrue(signposter.beginCalls.contains(.webViewConstruction))
        XCTAssertTrue(signposter.beginCalls.contains(.navigationRequestToCommit))
        XCTAssertTrue(signposter.beginCalls.contains(.commitToUsefulContent))
        XCTAssertEqual(signposter.endCalls.filter { $0.outcome == .failure }.count, 0)
        XCTAssertEqual(signposter.endCalls.last?.metadata.cacheEntryCount, 1)
    }

    func testWarmShortcutPresentationEndsWhenRetainedContentIsShown() throws {
        let signposter = PerformanceSignposterSpy()
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            performanceSignposter: signposter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)
        session.webView(webView, didFinish: nil)
        session.panelDidHide()
        let endCountBeforeShortcut = signposter.endCalls.count
        let token = signposter.begin(.shortcutPressToUsefulContent)
        session.beginShortcutPresentationMeasurement(
            signposter: signposter,
            token: token,
            retention: .warm
        )

        session.panelDidShow()

        XCTAssertEqual(signposter.endCalls.count, endCountBeforeShortcut + 1)
        XCTAssertEqual(signposter.endCalls.last?.outcome, .success)
        XCTAssertEqual(signposter.endCalls.last?.metadata.webViewRetention, .warm)
    }

    func testEvictedShortcutPresentationWaitsForNavigationReadiness() throws {
        let signposter = PerformanceSignposterSpy()
        let documentID = UUID()
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            interactionStateReader: { _ in "saved" },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(documentID)
            },
            performanceSignposter: signposter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        session.webView(try XCTUnwrap(session.webView), didFinish: nil)
        session.panelDidHide()
        session.handleMemoryPressure()
        XCTAssertEqual(session.webViewRetention, .evicted)
        let token = signposter.begin(.shortcutPressToUsefulContent)
        session.beginShortcutPresentationMeasurement(
            signposter: signposter,
            token: token,
            retention: .evicted
        )
        session.panelDidShow()

        XCTAssertNil(signposter.endCalls.first { $0.token == token })
        let restoredWebView = try XCTUnwrap(session.webView)
        session.webView(restoredWebView, didFinish: nil)
        XCTAssertNil(signposter.endCalls.first { $0.token == token })
        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: documentID),
            from: restoredWebView,
            generation: 3
        )
        let shortcutEnd = try XCTUnwrap(
            signposter.endCalls.first { $0.token == token }
        )
        XCTAssertEqual(shortcutEnd.outcome, .success)
        XCTAssertEqual(shortcutEnd.metadata.webViewRetention, .evicted)
    }

    func testInteractionStateRestorationMeasuresThroughUsefulContent() throws {
        let signposter = PerformanceSignposterSpy()
        let documentID = UUID()
        let first = try makePage(id: firstPageID, title: "First")
        let second = try makePage(id: secondPageID, title: "Second")
        var factoryURLs = [first.canonicalURL, second.canonicalURL, first.canonicalURL]
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            webViewFactory: { TrustedURLWebView(url: factoryURLs.removeFirst()) },
            interactionStateReader: { _ in "saved-state" },
            interactionStateWriter: { _, _ in },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(documentID)
            },
            performanceSignposter: signposter
        )

        session.activate(page: first)
        session.activate(page: second)
        session.activate(page: first)
        let restoredWebView = try XCTUnwrap(session.webView)
        let token = try XCTUnwrap(
            signposter.beginRecords.last {
                $0.operation == .interactionStateRestoreToUsefulContent
            }?.token
        )

        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: documentID),
            from: restoredWebView,
            generation: 5
        )

        XCTAssertEqual(
            signposter.endCalls.first { $0.token == token }?.outcome,
            .success
        )
    }

    func testRendererRecoveryMeasuresThroughUsefulContent() throws {
        let signposter = PerformanceSignposterSpy()
        let documentID = UUID()
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(documentID)
            },
            performanceSignposter: signposter
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)

        session.webViewWebContentProcessDidTerminate(webView)
        let token = try XCTUnwrap(
            signposter.beginRecords.last {
                $0.operation == .rendererRecoveryToUsefulContent
            }?.token
        )
        session.webView(webView, didCommit: nil)
        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: documentID),
            from: webView,
            generation: 3
        )

        XCTAssertEqual(
            signposter.endCalls.first { $0.token == token }?.outcome,
            .success
        )
    }

    func testHiddenWarmResumeEndsAfterAttachmentWorkRuns() throws {
        let signposter = PerformanceSignposterSpy()
        var attachmentActions: [@MainActor () -> Void] = []
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleAfterAttachment: { attachmentActions.append($0) },
            performanceSignposter: signposter
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        session.webView(webView, didFinish: nil)
        session.panelDidHide()

        session.panelDidShow()
        let token = try XCTUnwrap(
            signposter.beginRecords.last { $0.operation == .hiddenPanelWarmResume }?.token
        )
        XCTAssertNil(signposter.endCalls.first { $0.token == token })
        attachmentActions.forEach { $0() }

        XCTAssertEqual(
            signposter.endCalls.first { $0.token == token }?.outcome,
            .success
        )
    }

    func testShowingDifferentHiddenPageDoesNotMeasureWarmResume() throws {
        let signposter = PerformanceSignposterSpy()
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            performanceSignposter: signposter
        )
        session.activate(page: try makePage(id: firstPageID, title: "First"))
        session.panelDidHide()
        session.activate(page: try makePage(id: secondPageID, title: "Second"))

        session.panelDidShow()

        XCTAssertFalse(signposter.beginCalls.contains(.hiddenPanelWarmResume))
    }

    func testUsefulContentTimeoutFailsCurrentMeasurementsExactlyOnce() throws {
        let signposter = PerformanceSignposterSpy()
        let documentID = UUID()
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(documentID)
            },
            performanceSignposter: signposter
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        session.webView(webView, didCommit: nil)
        let token = try XCTUnwrap(
            signposter.beginRecords.last { $0.operation == .commitToUsefulContent }?.token
        )

        let message = NotionUsefulContentMessage(
            state: .timedOut,
            documentID: documentID
        )
        session.handleUsefulContent(message, from: webView, generation: 1)
        session.handleUsefulContent(message, from: webView, generation: 1)

        let ends = signposter.endCalls.filter { $0.token == token }
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends.first?.outcome, .failure)
    }

    func testStaleDocumentReadinessCannotEndReplacementNavigationMeasurement() throws {
        let signposter = PerformanceSignposterSpy()
        let staleDocumentID = UUID()
        var currentDocumentID = staleDocumentID
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(currentDocumentID)
            },
            performanceSignposter: signposter
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)
        session.webView(webView, didCommit: nil)

        session.reload()
        currentDocumentID = UUID()
        session.webView(webView, didCommit: nil)
        let replacementToken = try XCTUnwrap(
            signposter.beginRecords.last { $0.operation == .commitToUsefulContent }?.token
        )

        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: staleDocumentID),
            from: webView,
            generation: 1
        )
        XCTAssertNil(signposter.endCalls.first { $0.token == replacementToken })

        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: currentDocumentID),
            from: webView,
            generation: 1
        )
        XCTAssertEqual(
            signposter.endCalls.first { $0.token == replacementToken }?.outcome,
            .success
        )
    }

    func testReadinessWaitsForSameDocumentResolvedPageAdoption() throws {
        let signposter = PerformanceSignposterSpy()
        let documentID = UUID()
        let first = try makePage(id: firstPageID, title: "First")
        let resolved = try makePage(id: secondPageID, title: "Resolved")
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            webViewFactory: { TrustedURLWebView(url: resolved.canonicalURL) },
            usefulContentDocumentIdentifierReader: { _, completion in
                completion(documentID)
            },
            performanceSignposter: signposter
        )
        session.activate(page: first)
        let webView = try XCTUnwrap(session.webView)
        session.webView(webView, didCommit: nil)
        let token = try XCTUnwrap(
            signposter.beginRecords.last { $0.operation == .commitToUsefulContent }?.token
        )

        session.handleUsefulContent(
            NotionUsefulContentMessage(state: .ready, documentID: documentID),
            from: webView,
            generation: 1
        )
        XCTAssertNil(signposter.endCalls.first { $0.token == token })

        session.adoptResolvedPage(at: resolved.canonicalURL, from: webView)

        XCTAssertEqual(signposter.endCalls.first { $0.token == token }?.outcome, .success)
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

    func testActivateReloadsWhenSamePageIDUsesDifferentCanonicalRoute() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
        let oldPage = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/Roadmap-\(firstPageID)"))
        )
        let correctedPage = try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/acme/Roadmap-\(firstPageID)"))
        )

        session.activate(page: oldPage)
        session.activate(page: correctedPage)

        XCTAssertEqual(requests.map(\.url), [oldPage.canonicalURL, correctedPage.canonicalURL])
        XCTAssertEqual(session.activePage, correctedPage)
    }

    func testReloadPinnedPageForceLoadsCanonicalURLForActivePage() throws {
        var requests: [URLRequest] = []
        let session = NotionWebSession(loadRequest: { _, request in requests.append(request) })
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.reloadPinnedPage(page)

        XCTAssertEqual(requests.map(\.url), [page.canonicalURL, page.canonicalURL])
        XCTAssertEqual(session.activePage, page)
        XCTAssertEqual(session.state, .loading)
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
                host: "www.notion.com"
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
        XCTAssertEqual(session.state, .failed("Notion couldn't load this page."))
    }

    func testCancelledNavigationDoesNotReplaceLoadingStateWithFailure() throws {
        let session = NotionWebSession()
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        let webView = try XCTUnwrap(session.webView)

        navigationDelegate.webView?(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )

        XCTAssertEqual(session.state, .loading)
    }

    func testOfflineNavigationFailureEntersOfflineMode() throws {
        let session = NotionWebSession()
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let webView = try XCTUnwrap(session.webView)

        session.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )
        )

        XCTAssertEqual(session.state, .offline)
    }

    func testOfflineClassificationRejectsUnrelatedAndCancelledFailures() {
        XCTAssertTrue(
            NotionWebSession.isOfflineNavigationError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            )
        )
        XCTAssertFalse(
            NotionWebSession.isOfflineNavigationError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            )
        )
        XCTAssertFalse(
            NotionWebSession.isOfflineNavigationError(NSError(domain: "Test", code: 1))
        )
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

    func testRetainedPageCaptureSuspendsThenFocusesAndRestoresSelectionOnShow() throws {
        var captureCompletion: (@MainActor (Result<Any?, Error>) -> Void)?
        var evaluations: [NotionEditorSelectionEvaluation] = []
        var focusedWebViews: [WKWebView] = []
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = WKWebView()
        webView.load(URLRequest(url: page.canonicalURL))
        let container = NSView()
        container.addSubview(webView)
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            selectionEvaluator: { _, evaluation, completion in
                evaluations.append(evaluation)
                switch evaluation {
                case .capture:
                    captureCompletion = completion
                case .restore:
                    completion(.success(true))
                case .insert:
                    XCTFail("Unexpected insertion evaluation")
                    completion(.success(false))
                }
            },
            scheduleAfterAttachment: { $0() },
            focusWebView: { focusedWebViews.append($0) }
        )
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)

        session.panelDidHide()

        XCTAssertEqual(session.state, .active)
        XCTAssertTrue(webView.superview === container)
        XCTAssertEqual(evaluations, [.capture])

        captureCompletion?(.success(validSelectionSnapshotValue()))

        XCTAssertEqual(session.state, .suspended)
        XCTAssertNil(webView.superview)

        session.panelDidShow()

        XCTAssertTrue(session.webView === webView)
        XCTAssertEqual(session.state, .active)
        XCTAssertEqual(focusedWebViews, [webView])
        XCTAssertEqual(evaluations.count, 2)
        guard case .restore = evaluations.last else {
            return XCTFail("Expected the captured selection to be restored")
        }
    }

    func testShowingPanelBeforeCaptureCompletesPreventsLateSuspensionAndRestore() throws {
        var captureCompletion: (@MainActor (Result<Any?, Error>) -> Void)?
        var evaluations: [NotionEditorSelectionEvaluation] = []
        var focusCount = 0
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = WKWebView()
        webView.load(URLRequest(url: page.canonicalURL))
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            selectionEvaluator: { _, evaluation, completion in
                evaluations.append(evaluation)
                if case .capture = evaluation {
                    captureCompletion = completion
                } else {
                    completion(.success(true))
                }
            },
            scheduleAfterAttachment: { $0() },
            focusWebView: { _ in focusCount += 1 }
        )
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)

        session.panelDidHide()
        session.panelDidShow()
        captureCompletion?(.success(validSelectionSnapshotValue()))

        XCTAssertEqual(session.state, .active)
        XCTAssertTrue(session.webView === webView)
        XCTAssertEqual(focusCount, 1)
        XCTAssertEqual(evaluations, [.capture])
    }

    func testMissingMalformedAndFailedCaptureUseFocusOnlyFallback() throws {
        let results: [Result<Any?, Error>] = [
            .success(nil),
            .success(["version": 1, "token": "missing-paths"]),
            .failure(TestSelectionError.evaluationFailed),
        ]

        for result in results {
            var evaluations: [NotionEditorSelectionEvaluation] = []
            var focusCount = 0
            let page = try makePage(id: firstPageID, title: "Roadmap")
            let webView = WKWebView()
            webView.load(URLRequest(url: page.canonicalURL))
            let session = NotionWebSession(
                webView: webView,
                loadRequest: { _, _ in },
                scheduleEviction: { _, _ in AnyCancellable {} },
                selectionEvaluator: { _, evaluation, completion in
                    evaluations.append(evaluation)
                    switch evaluation {
                    case .capture:
                        completion(result)
                    case .restore:
                        completion(.success(true))
                    case .insert:
                        XCTFail("Unexpected insertion evaluation")
                        completion(.success(false))
                    }
                },
                scheduleAfterAttachment: { $0() },
                focusWebView: { _ in focusCount += 1 }
            )
            session.activate(page: page)
            let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
            navigationDelegate.webView?(webView, didFinish: nil)

            session.panelDidHide()
            session.panelDidShow()

            XCTAssertEqual(session.state, .active)
            XCTAssertEqual(focusCount, 1)
            XCTAssertEqual(evaluations, [.capture])
        }
    }

    func testNavigationInvalidatesCapturedSelectionBeforeRetainedShow() throws {
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = WKWebView()
        webView.load(URLRequest(url: page.canonicalURL))
        let recorder = SelectionEvaluationRecorder(
            captureResult: .success(validSelectionSnapshotValue())
        )
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            selectionEvaluator: recorder.evaluate,
            scheduleAfterAttachment: { $0() },
            focusWebView: { _ in }
        )
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)
        session.panelDidHide()

        navigationDelegate.webView?(webView, didStartProvisionalNavigation: nil)
        session.panelDidShow()

        XCTAssertEqual(recorder.restoreCount, 0)
        XCTAssertEqual(session.state, .loading)
    }

    func testReloadInvalidatesCapturedSelectionBeforeRetainedShow() throws {
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = WKWebView()
        webView.load(URLRequest(url: page.canonicalURL))
        let recorder = SelectionEvaluationRecorder(
            captureResult: .success(validSelectionSnapshotValue())
        )
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            selectionEvaluator: recorder.evaluate,
            scheduleAfterAttachment: { $0() },
            focusWebView: { _ in }
        )
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)
        session.panelDidHide()

        session.reload()
        session.panelDidShow()

        XCTAssertEqual(recorder.restoreCount, 0)
    }

    func testSavedCursorAdvancesAcrossOrderedInsertions() throws {
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = TrustedURLWebView(url: page.canonicalURL)
        var evaluations: [NotionEditorSelectionEvaluation] = []
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            selectionEvaluator: { _, evaluation, completion in
                evaluations.append(evaluation)
                switch evaluation {
                case .capture:
                    completion(.success(self.validSelectionSnapshotValue(token: "initial")))
                case .restore:
                    completion(.success(true))
                case let .insert(text, _):
                    completion(.success(self.validSelectionSnapshotValue(token: "after-\(text)")))
                }
            }
        )
        session.activate(page: page)
        var remembered = false
        var insertionResults: [Bool] = []

        session.rememberCurrentEditorCursor { remembered = $0 }
        session.insertAtSavedEditorCursor("alpha") { insertionResults.append($0) }
        session.insertAtSavedEditorCursor("beta") { insertionResults.append($0) }

        XCTAssertTrue(remembered)
        XCTAssertEqual(insertionResults, [true, true])
        XCTAssertEqual(evaluations.count, 3)
        guard case let .insert(_, firstSnapshot) = evaluations[1],
              case let .insert(_, secondSnapshot) = evaluations[2]
        else {
            return XCTFail("Expected two insertion evaluations")
        }
        XCTAssertEqual(firstSnapshot.token, "initial")
        XCTAssertEqual(secondSnapshot.token, "after-alpha")
    }

    func testPendingQuickCopyCursorCaptureCannotArmAfterInvalidation() throws {
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = TrustedURLWebView(url: page.canonicalURL)
        var captureCompletion: NotionEditorSelectionEvaluationCompletion?
        var results: [Bool] = []
        var invalidationCount = 0
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            selectionEvaluator: { _, evaluation, completion in
                switch evaluation {
                case .capture:
                    captureCompletion = completion
                case .restore:
                    completion(.success(true))
                case .insert:
                    completion(.success(self.validSelectionSnapshotValue(token: "advanced")))
                }
            }
        )
        session.activate(page: page)
        session.onQuickCopyTargetInvalidated = { invalidationCount += 1 }

        session.rememberCurrentEditorCursor { results.append($0) }
        session.reloadPinnedPage(page)
        captureCompletion?(.success(validSelectionSnapshotValue(token: "stale")))
        session.insertAtSavedEditorCursor("must not insert") { results.append($0) }

        XCTAssertGreaterThan(invalidationCount, 0)
        XCTAssertEqual(results, [false, false])
    }

    func testNavigationWhileCapturePendingCancelsCaptureAndSuspendsImmediately() throws {
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = WKWebView()
        webView.load(URLRequest(url: page.canonicalURL))
        let container = NSView()
        container.addSubview(webView)
        let recorder = SelectionEvaluationRecorder()
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            selectionEvaluator: recorder.evaluate,
            scheduleAfterAttachment: { $0() },
            focusWebView: { _ in }
        )
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)
        session.panelDidHide()

        navigationDelegate.webView?(webView, didStartProvisionalNavigation: nil)

        XCTAssertEqual(session.state, .suspended)
        XCTAssertNil(webView.superview)

        recorder.captureCompletion?(.success(validSelectionSnapshotValue()))
        session.panelDidShow()

        XCTAssertEqual(recorder.restoreCount, 0)
        XCTAssertEqual(session.state, .loading)
    }

    func testPageReplacementNeverRestoresPriorPageSelection() throws {
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        let webView = WKWebView()
        webView.load(URLRequest(url: firstPage.canonicalURL))
        let recorder = SelectionEvaluationRecorder(
            captureResult: .success(validSelectionSnapshotValue())
        )
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, _ in AnyCancellable {} },
            selectionEvaluator: recorder.evaluate,
            scheduleAfterAttachment: { $0() },
            focusWebView: { _ in }
        )
        session.activate(page: firstPage)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)
        session.panelDidHide()

        session.activate(page: secondPage)
        session.panelDidShow()

        XCTAssertEqual(recorder.restoreCount, 0)
        XCTAssertEqual(session.activePage, secondPage)
    }

    func testEvictionNeverRestoresSelectionIntoReplacementWebView() throws {
        var eviction: (@MainActor () -> Void)?
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = WKWebView()
        webView.load(URLRequest(url: page.canonicalURL))
        let recorder = SelectionEvaluationRecorder(
            captureResult: .success(validSelectionSnapshotValue())
        )
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            selectionEvaluator: recorder.evaluate,
            scheduleAfterAttachment: { $0() },
            focusWebView: { _ in }
        )
        session.activate(page: page)
        let navigationDelegate = try XCTUnwrap(session as WKNavigationDelegate)
        navigationDelegate.webView?(webView, didFinish: nil)
        session.panelDidHide()

        eviction?()
        session.panelDidShow()

        XCTAssertFalse(session.webView === webView)
        XCTAssertEqual(recorder.restoreCount, 0)
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

    func testIdleRendererTerminationReloadsCanonicalPageInSameWebView() throws {
        var createdWebViews: [WKWebView] = []
        var loads: [(WKWebView, URL?)] = []
        let session = NotionWebSession(
            loadRequest: { webView, request in
                loads.append((webView, request.url))
            },
            webViewFactory: {
                let webView = WKWebView()
                createdWebViews.append(webView)
                return webView
            }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let liveWebView = try XCTUnwrap(session.webView)
        session.webView(liveWebView, didFinish: nil)

        session.webViewWebContentProcessDidTerminate(liveWebView)

        XCTAssertTrue(session.webView === liveWebView)
        XCTAssertEqual(createdWebViews.count, 1)
        XCTAssertEqual(loads.map(\.1), [page.canonicalURL, page.canonicalURL])
        XCTAssertTrue(loads.allSatisfy { $0.0 === liveWebView })
        XCTAssertEqual(session.state, .loading)
        XCTAssertTrue(liveWebView.navigationDelegate === session)
        XCTAssertTrue(liveWebView.uiDelegate === session)

        session.webView(liveWebView, didFinish: nil)

        XCTAssertEqual(session.state, .active)
        XCTAssertTrue(session.webView === liveWebView)
    }

    func testNavigationTerminationRestartsOnlyCurrentCanonicalPage() throws {
        var loadedURLs: [URL?] = []
        let session = NotionWebSession(
            loadRequest: { _, request in loadedURLs.append(request.url) }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)

        session.webView(webView, didStartProvisionalNavigation: nil)
        session.webViewWebContentProcessDidTerminate(webView)

        XCTAssertEqual(loadedURLs, [page.canonicalURL, page.canonicalURL])
        XCTAssertTrue(session.webView === webView)
        XCTAssertEqual(session.activePage, page)
        XCTAssertEqual(session.state, .loading)
    }

    func testStashedRendererTerminationRecoversWithoutReplacingWebView() throws {
        var creationCount = 0
        var loadedURLs: [URL?] = []
        let session = NotionWebSession(
            loadRequest: { _, request in loadedURLs.append(request.url) },
            webViewFactory: {
                creationCount += 1
                return WKWebView()
            },
            scheduleEviction: { _, _ in AnyCancellable {} }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let liveWebView = try XCTUnwrap(session.webView)
        session.webView(liveWebView, didFinish: nil)
        session.panelDidHide()

        session.webViewWebContentProcessDidTerminate(liveWebView)

        XCTAssertTrue(session.webView === liveWebView)
        XCTAssertEqual(session.state, .suspended)
        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(loadedURLs, [page.canonicalURL, page.canonicalURL])

        session.webView(liveWebView, didFinish: nil)

        session.panelDidShow()

        XCTAssertTrue(session.webView === liveWebView)
        XCTAssertEqual(session.state, .active)
        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(loadedURLs, [page.canonicalURL, page.canonicalURL])
    }

    func testFailedAutomaticRecoverySurfacesRetryableNativeFailure() throws {
        var loadedURLs: [URL?] = []
        let session = NotionWebSession(
            loadRequest: { _, request in loadedURLs.append(request.url) }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)
        session.webViewWebContentProcessDidTerminate(webView)

        session.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "Test", code: 1)
        )
        session.webView(webView, didFinish: nil)

        guard case .failed = session.state else {
            return XCTFail("Expected a retryable native failure state")
        }
        let chrome = PiPChromeView(webSession: session)
        XCTAssertTrue(String(reflecting: chrome.body).contains("Try Again"))

        session.reloadPinnedPage(page)

        XCTAssertEqual(loadedURLs, [page.canonicalURL, page.canonicalURL, page.canonicalURL])
        XCTAssertEqual(session.state, .loading)
    }

    func testRepeatedTerminationStopsAfterOneAutomaticReload() throws {
        var loadedURLs: [URL?] = []
        let session = NotionWebSession(
            loadRequest: { _, request in loadedURLs.append(request.url) }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")
        session.activate(page: page)
        let webView = try XCTUnwrap(session.webView)

        session.webViewWebContentProcessDidTerminate(webView)
        session.webViewWebContentProcessDidTerminate(webView)
        session.webViewWebContentProcessDidTerminate(webView)
        session.webView(webView, didStartProvisionalNavigation: nil)
        session.webView(webView, didFinish: nil)

        XCTAssertEqual(loadedURLs, [page.canonicalURL, page.canonicalURL])
        XCTAssertTrue(session.webView === webView)
        guard case .failed = session.state else {
            return XCTFail("Expected repeated termination to stop automatic reloads")
        }
    }

    func testSuccessfulRecoveryRestoresSamePageScrollButNeverDOMSelection() throws {
        let page = try makePage(id: firstPageID, title: "Roadmap")
        let webView = TrustedURLWebView(url: page.canonicalURL)
        var appliedRestorations: [DurablePageRestoration] = []
        var insertionEvaluationCount = 0
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { _, _ in },
            scrollRestorer: { _, restoration in
                appliedRestorations.append(restoration)
            },
            selectionEvaluator: { _, evaluation, completion in
                switch evaluation {
                case .capture:
                    completion(.success(self.validSelectionSnapshotValue()))
                case .restore:
                    XCTFail("Terminated DOM selection must never be restored")
                    completion(.success(false))
                case .insert:
                    insertionEvaluationCount += 1
                    completion(.success(self.validSelectionSnapshotValue()))
                }
            }
        )
        session.activate(page: page)
        var remembered = false
        session.rememberCurrentEditorCursor { remembered = $0 }
        session.handleScrollSnapshot(NotionScrollSnapshot(x: 8, y: 480, progress: 0.4))

        session.webViewWebContentProcessDidTerminate(webView)
        var insertionSucceeded = true
        session.insertAtSavedEditorCursor("unsafe") { insertionSucceeded = $0 }
        session.webView(webView, didFinish: nil)

        XCTAssertTrue(remembered)
        XCTAssertFalse(insertionSucceeded)
        XCTAssertEqual(insertionEvaluationCount, 0)
        let restoration = try XCTUnwrap(appliedRestorations.first)
        XCTAssertEqual(appliedRestorations.count, 1)
        XCTAssertEqual(restoration.pageID, page.pageID)
        XCTAssertEqual(restoration.lastURL, page.canonicalURL)
        XCTAssertEqual(restoration.scrollX, 8)
        XCTAssertEqual(restoration.scrollY, 480)
        XCTAssertEqual(restoration.scrollProgress, 0.4)
    }

    func testRecoveryCompletesAfterValidatedRedirectWithoutRestoringOldPageScroll() throws {
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        let webView = WKWebView()
        var appliedRestorations: [DurablePageRestoration] = []
        let session = NotionWebSession(
            webView: webView,
            loadRequest: { webView, request in webView.load(request) },
            scrollRestorer: { _, restoration in
                appliedRestorations.append(restoration)
            }
        )
        session.onPageResolved = { _ in }
        session.activate(page: firstPage)
        session.handleScrollSnapshot(NotionScrollSnapshot(x: 8, y: 480, progress: 0.4))
        session.webViewWebContentProcessDidTerminate(webView)

        webView.load(URLRequest(url: secondPage.canonicalURL))
        session.webView(webView, didFinish: nil)

        XCTAssertTrue(session.webView === webView)
        XCTAssertEqual(session.activePage, secondPage)
        XCTAssertEqual(session.state, .active)
        XCTAssertTrue(appliedRestorations.isEmpty)
    }

    func testTerminationDuringPageSwitchCannotLetStaleCallbacksReplaceSelection() throws {
        var loads: [(WKWebView, URL?)] = []
        var interactionReadCount = 0
        var capturedRestorations: [DurablePageRestoration] = []
        let session = NotionWebSession(
            loadRequest: { webView, request in loads.append((webView, request.url)) },
            interactionStateReader: { _ in
                interactionReadCount += 1
                return "must-not-survive-termination"
            }
        )
        session.onRestorationCaptured = { capturedRestorations.append($0) }
        let firstPage = try makePage(id: firstPageID, title: "Roadmap")
        let secondPage = try makePage(id: secondPageID, title: "Notes")
        session.activate(page: firstPage)
        let staleWebView = try XCTUnwrap(session.webView)
        session.webViewWebContentProcessDidTerminate(staleWebView)
        session.activate(page: secondPage)
        let currentWebView = try XCTUnwrap(session.webView)
        XCTAssertFalse(currentWebView === staleWebView)

        session.webView(staleWebView, didStartProvisionalNavigation: nil)
        session.webView(
            staleWebView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: "Test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Stale provisional failure"]
            )
        )
        session.webView(
            staleWebView,
            didFail: nil,
            withError: NSError(
                domain: "Test",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Stale committed failure"]
            )
        )
        session.webView(staleWebView, didFinish: nil)
        session.webViewWebContentProcessDidTerminate(staleWebView)
        session.adoptResolvedPage(at: firstPage.canonicalURL, from: staleWebView)
        session.handleEditorActivity(.typingStarted, from: staleWebView)

        XCTAssertEqual(session.state, .loading)
        XCTAssertEqual(session.activePage, secondPage)
        XCTAssertFalse(session.isTypingInPage)
        XCTAssertEqual(interactionReadCount, 0)
        XCTAssertTrue(capturedRestorations.isEmpty)
        XCTAssertEqual(loads.map(\.1), [
            firstPage.canonicalURL,
            firstPage.canonicalURL,
            secondPage.canonicalURL,
        ])
    }

    func testRendererTerminationRefreshesBridgeAndObservationGeneration() throws {
        var bridgeRemovalCount = 0
        var observationInvalidationCount = 0
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            invalidateURLObservation: { observation in
                observationInvalidationCount += 1
                observation.invalidate()
            },
            removeActivityBridge: { controller in
                bridgeRemovalCount += 1
                controller.removeScriptMessageHandler(
                    forName: NotionEditorActivityBridge.handlerName,
                    contentWorld: .page
                )
                controller.removeScriptMessageHandler(
                    forName: NotionScrollBridge.handlerName,
                    contentWorld: .page
                )
                controller.removeScriptMessageHandler(
                    forName: NotionUsefulContentBridge.handlerName,
                    contentWorld: .page
                )
                controller.removeAllUserScripts()
            }
        )
        session.activate(page: try makePage(id: firstPageID, title: "Roadmap"))
        let retiredWebView = try XCTUnwrap(session.webView)

        session.webViewWebContentProcessDidTerminate(retiredWebView)
        session.webViewWebContentProcessDidTerminate(retiredWebView)

        XCTAssertEqual(bridgeRemovalCount, 2)
        XCTAssertEqual(observationInvalidationCount, 2)
        XCTAssertTrue(session.webView === retiredWebView)
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

    func testRestoredInteractionStateIsReleasedAfterApplyingToReplacementWebView() throws {
        var eviction: (@MainActor () -> Void)?
        weak var restoredState: InteractionStateSentinel?
        let session = NotionWebSession(
            loadRequest: { _, _ in },
            scheduleEviction: { _, action in
                eviction = action
                return AnyCancellable {}
            },
            interactionStateReader: { _ in
                let state = InteractionStateSentinel()
                restoredState = state
                return state
            },
            interactionStateWriter: { _, _ in }
        )
        let page = try makePage(id: firstPageID, title: "Roadmap")

        session.activate(page: page)
        session.panelDidHide()
        eviction?()
        XCTAssertNotNil(restoredState)

        session.panelDidShow()

        XCTAssertNil(restoredState)
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
        XCTAssertEqual(session.state, .failed("Notion couldn't load this page."))

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
                host: "www.notion.com"
            ),
            .typingStarted
        )
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "editingEnded",
                isMainFrame: true,
                scheme: "https",
                host: "notion.com"
            ),
            .editingEnded
        )
        XCTAssertEqual(
            NotionEditorActivityBridge.activity(
                from: "editingEnded",
                isMainFrame: true,
                scheme: "https",
                host: "www.notion.so"
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

    func testTopControlsNeverChangeWebViewLayoutHeight() {
        XCTAssertEqual(PiPChromeView.topControlsReservedHeight(isVisible: false), 0)
        XCTAssertEqual(PiPChromeView.topControlsReservedHeight(isVisible: true), 0)
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

    func testEditorActivityScriptExecutesEditableEventLifecycleWithoutJavaScriptErrors() async throws {
        let webView = WKWebView()
        let session = NotionWebSession(webView: webView)
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <body>
                <input id="editor" type="text">
                <script>
                  window.__notionPiPTestErrors = [];
                  window.addEventListener('error', (event) => {
                    window.__notionPiPTestErrors.push(event.message);
                  });
                </script>
              </body>
            </html>
            """,
            baseURL: try XCTUnwrap(URL(string: "https://www.notion.so/activity-fixture"))
        )
        try await waitForJavaScriptCondition(in: webView) {
            "document.readyState === 'complete' && Boolean(document.querySelector('#editor'))"
        }

        try await dispatchEditorActivity(
            """
            const editor = document.querySelector('#editor');
            editor.focus();
            editor.dispatchEvent(new InputEvent('beforeinput', {
              bubbles: true,
              inputType: 'insertText',
              data: 'a',
            }));
            """,
            in: webView
        )
        try await waitForCondition { session.isTypingInPage }

        try await dispatchEditorActivity(
            "document.dispatchEvent(new PointerEvent('pointermove', { bubbles: true }));",
            in: webView
        )
        try await waitForCondition { !session.isTypingInPage }

        try await beginTyping(in: webView)
        try await waitForCondition { session.isTypingInPage }
        try await dispatchEditorActivity(
            "document.querySelector('#editor').blur();",
            in: webView
        )
        try await waitForCondition { !session.isTypingInPage }

        for key in ["Tab", "Escape"] {
            try await beginTyping(in: webView)
            try await waitForCondition { session.isTypingInPage }
            try await dispatchEditorActivity(
                """
                document.querySelector('#editor').dispatchEvent(
                  new KeyboardEvent('keydown', { key: '\(key)', bubbles: true })
                );
                """,
                in: webView
            )
            try await waitForCondition { !session.isTypingInPage }
        }

        let errors = try await webView.evaluateJavaScript(
            "window.__notionPiPTestErrors"
        ) as? [String]
        XCTAssertEqual(errors, [])
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

        XCTAssertEqual(PiPChromeView.primaryActionAccessibilityLabel, "New Notion Page")
        XCTAssertEqual(PiPChromeView.primaryActionHelp, "Create a page in the Notion app")
        XCTAssertEqual(PiPChromeView.reloadAccessibilityLabel, "Re-pin current Notion page")
        XCTAssertEqual(PiPChromeView.reloadHelp, "Re-pin the current Notion page")
        XCTAssertEqual(PiPChromeView.stashAccessibilityLabel, "Stash Notion PiP to Side")
        XCTAssertEqual(
            PiPChromeView.stashHelp,
            "Move the Notion PiP to the nearest screen edge"
        )
    }

    func testScrollRestorationUsesOneWebContentTransactionWithInternalRetryLoop() async throws {
        let webView = WKWebView()
        var calls: [(script: String, arguments: [String: Any])] = []
        let restoration = try DurablePageRestoration(
            pageID: firstPageID,
            validatingLastURL: XCTUnwrap(
                URL(string: "https://www.notion.com/Roadmap-\(firstPageID)")
            ),
            scrollX: 0,
            scrollY: 2_000,
            scrollProgress: 0.5,
            updatedAt: Date()
        )

        NotionWebSession.restoreScroll(
            in: webView,
            restoration: restoration,
            callAsyncJavaScript: { _, script, arguments in
                calls.append((script, arguments))
                return true
            }
        )

        try await waitForCondition { calls.count == 1 }
        let call = try XCTUnwrap(calls.first)
        XCTAssertTrue(call.script.contains("new Promise"))
        XCTAssertTrue(call.script.contains("requestAnimationFrame(apply)"))
        XCTAssertTrue(call.script.contains("performance.now() + timeoutMilliseconds"))
        XCTAssertEqual(call.arguments["scrollX"] as? Double, 0)
        XCTAssertEqual(call.arguments["scrollY"] as? Double, 2_000)
        XCTAssertEqual(call.arguments["scrollProgress"] as? Double, 0.5)
        XCTAssertEqual(call.arguments["timeoutMilliseconds"] as? Int, 2_000)
        XCTAssertEqual(call.arguments["tolerancePixels"] as? Int, 4)
        XCTAssertEqual(call.arguments["retryDelayMilliseconds"] as? Int, 100)
    }

    private func makePage(id: String, title: String) throws -> NotionPageReference {
        try NotionPageReference(
            validating: XCTUnwrap(URL(string: "https://www.notion.so/\(title)-\(id)"))
        )
    }

    private func beginTyping(in webView: WKWebView) async throws {
        try await dispatchEditorActivity(
            """
            const editor = document.querySelector('#editor');
            editor.focus();
            editor.dispatchEvent(new InputEvent('beforeinput', {
              bubbles: true,
              inputType: 'insertText',
              data: 'a',
            }));
            """,
            in: webView
        )
    }

    private func dispatchEditorActivity(
        _ source: String,
        in webView: WKWebView
    ) async throws {
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              \(source)
              return true;
            })();
            """
        )
    }

    private func waitForCondition(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NotionWebSessionTestError.timeout
    }

    private func waitForJavaScriptCondition(
        in webView: WKWebView,
        timeout: Duration = .seconds(3),
        expression: () -> String
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let matches = try? await webView.evaluateJavaScript(expression()) as? Bool,
               matches
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NotionWebSessionTestError.timeout
    }

    private func validSelectionSnapshotValue(
        token: String = "selection-token"
    ) -> [String: Any] {
        [
            "version": 1,
            "token": token,
            "editablePath": [1, 2],
            "anchorPath": [0],
            "anchorOffset": 3,
            "focusPath": [0],
            "focusOffset": 7,
        ]
    }
}

private final class InteractionStateSentinel {}

private final class TrustedURLWebView: WKWebView {
    private let trustedURL: URL

    init(url: URL) {
        trustedURL = url
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var url: URL? {
        trustedURL
    }
}

private enum TestSelectionError: Error {
    case evaluationFailed
}

@MainActor
private final class SelectionEvaluationRecorder {
    private(set) var evaluations: [NotionEditorSelectionEvaluation] = []
    var captureCompletion: NotionEditorSelectionEvaluationCompletion?
    var captureResult: Result<Any?, Error>?

    var restoreCount: Int {
        evaluations.reduce(into: 0) { count, evaluation in
            if case .restore = evaluation {
                count += 1
            }
        }
    }

    init(captureResult: Result<Any?, Error>? = nil) {
        self.captureResult = captureResult
    }

    func evaluate(
        _ webView: WKWebView,
        _ evaluation: NotionEditorSelectionEvaluation,
        _ completion: @escaping NotionEditorSelectionEvaluationCompletion
    ) {
        evaluations.append(evaluation)
        switch evaluation {
        case .capture:
            if let captureResult {
                completion(captureResult)
            } else {
                captureCompletion = completion
            }
        case .restore:
            completion(.success(true))
        case .insert:
            XCTFail("Unexpected insertion evaluation")
            completion(.success(false))
        }
    }
}

private enum NotionWebSessionTestError: Error {
    case timeout
}
