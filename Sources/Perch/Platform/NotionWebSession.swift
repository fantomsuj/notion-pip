import Combine
import AppKit
import WebKit

typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void
typealias NotionWebViewFactory = @MainActor () -> WKWebView
typealias NotionWebScrollRestorer = @MainActor (WKWebView, DurablePageRestoration) -> Void
typealias NotionWebScrollJavaScriptCaller = @MainActor (
    WKWebView,
    String,
    [String: Any]
) async throws -> Any?
typealias NotionUsefulContentDocumentIdentifierReader = @MainActor (
    WKWebView,
    @escaping @MainActor (UUID?) -> Void
) -> Void
typealias NotionWebEvictionScheduler = @MainActor (
    TimeInterval,
    @escaping @MainActor () -> Void
) -> AnyCancellable
typealias NotionWebAttachmentScheduler = @MainActor (
    @escaping @MainActor () -> Void
) -> Void
typealias NotionWebURLObservationInvalidator = @MainActor (NSKeyValueObservation) -> Void

@MainActor
protocol NotionPageLoading: AnyObject {
    var webViewRetention: WebViewRetention { get }
    func activate(page: NotionPageReference)
    func activate(page: NotionPageReference, restoration: DurablePageRestoration?)
    func reloadPinnedPage(_ page: NotionPageReference)
    func reselect(page: NotionPageReference)
    func panelDidShow()
    func panelDidHide()
    func beginShortcutPresentationMeasurement(
        signposter: any PerformanceSignposting,
        token: PerformanceIntervalToken?,
        retention: WebViewRetention
    )
}

extension NotionPageLoading {
    var webViewRetention: WebViewRetention { .unknown }
    func activate(page: NotionPageReference, restoration: DurablePageRestoration?) {
        activate(page: page)
    }
    func reselect(page: NotionPageReference) {}
    func panelDidShow() {}
    func panelDidHide() {}
    func beginShortcutPresentationMeasurement(
        signposter: any PerformanceSignposting,
        token: PerformanceIntervalToken?,
        retention: WebViewRetention
    ) {}
}

@MainActor
enum NotionWebSessionState: Equatable {
    case unloaded
    case loading
    case active
    case suspended
    case offline
    case failed(String)
}

@MainActor
final class NotionWebSession: NSObject, NotionPageLoading, ObservableObject,
    NotionWebScriptMessageHandling, QuickCopyInsertionTarget
{
    private enum WebContentRecoveryState: Equatable {
        case ready
        case attempting(pageID: String)
        case failed(pageID: String)
    }

    static let warmRetentionInterval = NotionWebLifecycleController.defaultWarmRetentionInterval

    @Published private(set) var webView: WKWebView?
    var state: NotionWebSessionState { lifecycleController.state }
    @Published private(set) var browserLoginState: NotionBrowserLoginState = .idle
    @Published private(set) var isTypingInPage = false
    private(set) var activePage: NotionPageReference?
    var onPageResolved: (@MainActor (NotionPageReference) -> Void)?
    private let openURL: @MainActor (URL) -> Void
    private let browserAuthenticationSessionFactory:
        NotionBrowserAuthenticationSessionFactory
    private let browserLoginPresentationAnchor: @MainActor (WKWebView) -> NSWindow?
    private let browserLoginCurrentURL: @MainActor (WKWebView) -> URL?
    private let browserHandoffRedeemer: NotionBrowserHandoffRedeemer
    private let scheduleBrowserLoginTimeout: NotionWebEvictionScheduler
    private let loadRequest: NotionWebRequestLoader
    private let webViewFactory: NotionWebViewFactory
    private let lifecycleController: NotionWebLifecycleController
    private let navigationDecisionPolicy = NotionWebNavigationPolicy()
    private let popupCoordinator: any NotionWebPopupCoordinating
    private let pageStateRestoration = NotionPageStateRestorationCoordinator()
    private let pauseMedia: @MainActor (WKWebView) -> Void
    private let stopLoading: @MainActor (WKWebView) -> Void
    private let interactionStateReader: @MainActor (WKWebView) -> Any?
    private let interactionStateWriter: @MainActor (WKWebView, Any) -> Void
    private let endEditing: @MainActor (WKWebView) -> Void
    private let scrollRestorer: NotionWebScrollRestorer
    private let selectionEvaluator: NotionEditorSelectionEvaluator
    private let scheduleAfterAttachment: NotionWebAttachmentScheduler
    private let focusWebView: @MainActor (WKWebView) -> Void
    private let invalidateURLObservation: NotionWebURLObservationInvalidator
    private let usefulContentDocumentIdentifierReader:
        NotionUsefulContentDocumentIdentifierReader
    private let scriptMessageCoordinator: NotionWebScriptMessageCoordinator
    private let performanceSignposter: (any PerformanceSignposting)?
    private var urlObservation: NSKeyValueObservation?
    private var lifecycleObservation: AnyCancellable?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var panelIsVisible: Bool { lifecycleController.isVisible }
    private var loadedPageID: String?
    private var loadedRequestURL: URL?
    private var webContentRecoveryState = WebContentRecoveryState.ready
    private var restorationToken: PerformanceIntervalToken?
    private var navigationRequestToCommitToken: PerformanceIntervalToken?
    private var commitToUsefulContentToken: PerformanceIntervalToken?
    private var interactionStateRestoreToUsefulContentToken: PerformanceIntervalToken?
    private var rendererRecoveryToUsefulContentToken: PerformanceIntervalToken?
    private var usefulContentMeasurementGeneration: UInt = 0
    private var pendingUsefulContentMessage: NotionUsefulContentMessage?
    private var completedUsefulContentDocumentID: UUID?
    private var shortcutPresentationMeasurement: (
        signposter: any PerformanceSignposting,
        token: PerformanceIntervalToken?,
        retention: WebViewRetention
    )?
    private var browserAuthenticationSession:
        (any NotionBrowserAuthenticationSession)?
    private var browserLoginAttemptGeneration: UInt = 0
    private var browserLoginPageID: String?
    private var browserLoginRestoringPageID: String?
    private var browserLoginTimeoutCancellable: AnyCancellable?
    private var browserHandoffRedemptionCancellable: AnyCancellable?
    var onRestorationCaptured: (@MainActor (DurablePageRestoration) -> Void)?
    var onQuickCopyTargetInvalidated: (@MainActor () -> Void)?
    private var selectionCaptureGeneration = 0
    private var savedEditorSelection: (
        pageID: String,
        snapshot: NotionEditorSelectionSnapshot
    )?

    func rememberCurrentEditorCursor(completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard let webView, let pageID = activePage?.pageID,
              loadedPageID == pageID, Self.isTrustedSelectionContext(webView, pageID: pageID)
        else { completion(false); return }
        let generation = selectionCaptureGeneration
        selectionEvaluator(webView, .capture) { [weak self, weak webView] result in
            guard let self, let webView,
                  self.selectionCaptureGeneration == generation,
                  self.webView === webView,
                  self.activePage?.pageID == pageID,
                  self.loadedPageID == pageID,
                  case let .success(value) = result,
                  let snapshot = NotionEditorSelectionSnapshot(javaScriptValue: value)
            else { completion(false); return }
            self.savedEditorSelection = (pageID, snapshot)
            completion(true)
        }
    }

    func insertAtSavedEditorCursor(
        _ text: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !text.isEmpty, let webView, let pageID = activePage?.pageID,
              loadedPageID == pageID, savedEditorSelection?.pageID == pageID,
              let snapshot = savedEditorSelection?.snapshot,
              Self.isTrustedSelectionContext(webView, pageID: pageID)
        else { completion(false); return }
        selectionEvaluator(webView, .insert(text, at: snapshot)) { [weak self] result in
            guard let self,
                  case let .success(value) = result,
                  let nextSnapshot = NotionEditorSelectionSnapshot(javaScriptValue: value),
                  self.activePage?.pageID == pageID,
                  self.loadedPageID == pageID,
                  self.webView === webView
            else {
                completion(false)
                return
            }
            self.savedEditorSelection = (pageID, nextSnapshot)
            completion(true)
        }
    }

    var shouldHostWebView: Bool {
        lifecycleController.shouldHostWebView(hasWebView: webView != nil)
    }

    var webViewRetention: WebViewRetention {
        webView == nil ? .evicted : .warm
    }

    init(
        webView: WKWebView? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        browserAuthenticationSessionFactory:
            @escaping NotionBrowserAuthenticationSessionFactory = {
                url,
                callbackScheme,
                anchor,
                completion in
                SystemNotionBrowserAuthenticationSession(
                    url: url,
                    callbackScheme: callbackScheme,
                    anchor: anchor,
                    completion: completion
                )
            },
        browserLoginPresentationAnchor: @escaping @MainActor (WKWebView) -> NSWindow? = {
            $0.window
        },
        browserLoginCurrentURL: @escaping @MainActor (WKWebView) -> URL? = {
            $0.url
        },
        browserHandoffRedeemer: @escaping NotionBrowserHandoffRedeemer = {
            webView,
            code,
            completion in
            NotionBrowserHandoffRedemption.redeem(
                in: webView,
                code: code,
                completion: completion
            )
        },
        scheduleBrowserLoginTimeout: @escaping NotionWebEvictionScheduler = {
            interval,
            action in
            let task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                action()
            }
            return AnyCancellable { task.cancel() }
        },
        loadRequest: @escaping NotionWebRequestLoader = { webView, request in
            webView.load(request)
        },
        popupCoordinator: (any NotionWebPopupCoordinating)? = nil,
        webViewFactory: @escaping NotionWebViewFactory = { NotionWebSession.makeWebView() },
        scheduleEviction: @escaping NotionWebEvictionScheduler = { interval, action in
            let task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                action()
            }
            return AnyCancellable { task.cancel() }
        },
        pauseMedia: @escaping @MainActor (WKWebView) -> Void = { webView in
            Task { @MainActor in
                await webView.pauseAllMediaPlayback()
            }
        },
        stopLoading: @escaping @MainActor (WKWebView) -> Void = { $0.stopLoading() },
        interactionStateReader: @escaping @MainActor (WKWebView) -> Any? = {
            $0.interactionState
        },
        interactionStateWriter: @escaping @MainActor (WKWebView, Any) -> Void = {
            $0.interactionState = $1
        },
        endEditing: @escaping @MainActor (WKWebView) -> Void = { webView in
            webView.window?.endEditing(for: webView)
            _ = webView.window?.makeFirstResponder(nil)
        },
        scrollRestorer: @escaping NotionWebScrollRestorer = {
            webView,
            restoration in
            NotionWebSession.restoreScroll(in: webView, restoration: restoration)
        },
        selectionEvaluator: @escaping NotionEditorSelectionEvaluator = {
            webView,
            evaluation,
            completion in
            webView.evaluateJavaScript(evaluation.script) { value, error in
                MainActor.assumeIsolated {
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(value))
                    }
                }
            }
        },
        scheduleAfterAttachment: @escaping NotionWebAttachmentScheduler = { action in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    action()
                }
            }
        },
        focusWebView: @escaping @MainActor (WKWebView) -> Void = { webView in
            _ = webView.window?.makeFirstResponder(webView)
        },
        invalidateURLObservation: @escaping NotionWebURLObservationInvalidator = {
            $0.invalidate()
        },
        removeActivityBridge: @escaping NotionWebActivityBridgeRemover = {
            $0.removeScriptMessageHandler(
                forName: NotionEditorActivityBridge.handlerName,
                contentWorld: .page
            )
            $0.removeScriptMessageHandler(
                forName: NotionScrollBridge.handlerName,
                contentWorld: .page
            )
            $0.removeScriptMessageHandler(
                forName: NotionUsefulContentBridge.handlerName,
                contentWorld: .page
            )
            $0.removeAllUserScripts()
        },
        usefulContentDocumentIdentifierReader:
            @escaping NotionUsefulContentDocumentIdentifierReader = { webView, completion in
                webView.evaluateJavaScript(
                    NotionUsefulContentBridge.documentIdentifierExpression
                ) { value, _ in
                    MainActor.assumeIsolated {
                        let documentID = (value as? String).flatMap(UUID.init(uuidString:))
                        completion(documentID)
                    }
                }
            },
        performanceSignposter: (any PerformanceSignposting)? = AppPerformanceSignposter.shared
    ) {
        self.webView = nil
        self.openURL = openURL
        self.browserAuthenticationSessionFactory = browserAuthenticationSessionFactory
        self.browserLoginPresentationAnchor = browserLoginPresentationAnchor
        self.browserLoginCurrentURL = browserLoginCurrentURL
        self.browserHandoffRedeemer = browserHandoffRedeemer
        self.scheduleBrowserLoginTimeout = scheduleBrowserLoginTimeout
        self.loadRequest = loadRequest
        self.popupCoordinator = popupCoordinator
            ?? NotionWebPopupCoordinator(openURL: openURL)
        self.webViewFactory = webViewFactory
        self.lifecycleController = NotionWebLifecycleController(scheduleEviction: scheduleEviction)
        self.pauseMedia = pauseMedia
        self.stopLoading = stopLoading
        self.interactionStateReader = interactionStateReader
        self.interactionStateWriter = interactionStateWriter
        self.endEditing = endEditing
        self.scrollRestorer = scrollRestorer
        self.selectionEvaluator = selectionEvaluator
        self.scheduleAfterAttachment = scheduleAfterAttachment
        self.focusWebView = focusWebView
        self.invalidateURLObservation = invalidateURLObservation
        self.usefulContentDocumentIdentifierReader =
            usefulContentDocumentIdentifierReader
        self.scriptMessageCoordinator = NotionWebScriptMessageCoordinator(
            removeBridges: removeActivityBridge
        )
        self.performanceSignposter = performanceSignposter
        super.init()
        scriptMessageCoordinator.delegate = self
        lifecycleObservation = lifecycleController.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        lifecycleController.onEvictionRequested = { [weak self] in
            self?.evictWarmWebView(afterLifecycleDecision: true)
        }
        if let webView {
            configure(webView)
        }
        installMemoryPressureSource()
    }

    private func configure(_ webView: WKWebView) {
        self.webView = webView
        let generation = scriptMessageCoordinator.install(
            in: webView.configuration.userContentController
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.browserLoginRouteDidChange(to: webView.url)
                self?.adoptResolvedPage(
                    at: webView.url,
                    from: webView,
                    generation: generation
                )
                self?.retryPendingUsefulContentMessage()
            }
        }
    }

    private func refreshDOMBridges(afterTerminationOf webView: WKWebView) {
        guard isCurrent(webView) else { return }
        if let urlObservation {
            invalidateURLObservation(urlObservation)
            self.urlObservation = nil
        }
        scriptMessageCoordinator.remove(from: webView.configuration.userContentController)
        configure(webView)
    }

    @discardableResult
    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }
        let constructionToken = performanceSignposter?.begin(.webViewConstruction)
        let webView = webViewFactory()
        configure(webView)
        performanceSignposter?.end(constructionToken, outcome: .success)
        return webView
    }

    func activate(page: NotionPageReference) {
        activate(page: page, restoration: nil)
    }

    func activate(
        page: NotionPageReference,
        restoration: DurablePageRestoration?
    ) {
        guard activePage?.canonicalURL != page.canonicalURL else {
            return
        }

        if let outgoingPage = activePage, let webView {
            cancelBrowserLogin(resetState: true)
            invalidateEditorSelection()
            if outgoingPage.pageID == page.pageID {
                pageStateRestoration.discardCachedState(for: page.pageID)
                _ = retire(webView)
            } else {
                captureAndTearDown(webView, page: outgoingPage)
            }
        }
        activePage = page
        webContentRecoveryState = .ready
        revealTopControls()
        pageStateRestoration.prepareActivation(of: page, restoration: restoration)
        guard panelIsVisible, state != .suspended else {
            if !panelIsVisible, webView != nil {
                suspendWebViewIfNeeded()
            }
            return
        }
        restoreOrLoad(page: page)
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        cancelBrowserLogin(resetState: true)
        invalidateEditorSelection()
        activePage = page
        webContentRecoveryState = .ready
        revealTopControls()
        pageStateRestoration.prepareReload(of: page)
        load(page.canonicalURL, pageID: page.pageID)
    }

    func panelDidShow() {
        let wasHidden = !panelIsVisible
        let retainedWebView = webView
        let retainedPageID = loadedPageID
        let warmResumeSignposter = performanceSignposter
        let measuresWarmResume = wasHidden
            && retainedWebView != nil
            && retainedPageID != nil
            && retainedPageID == activePage?.pageID
        let warmResumeToken = measuresWarmResume
            ? warmResumeSignposter?.begin(.hiddenPanelWarmResume)
            : nil
        selectionCaptureGeneration &+= 1
        let resumeCommand = lifecycleController.panelDidShow(
            hasWebView: webView != nil,
            hasActivePage: activePage != nil
        )
        if resumeCommand == .loadActivePage, let activePage {
            restoreOrLoad(page: activePage)
        } else if let activePage,
                  webView != nil,
                  loadedPageID != activePage.pageID
        {
            load(activePage.canonicalURL, pageID: activePage.pageID)
        }
        if wasHidden,
           let retainedWebView,
           webView === retainedWebView,
           retainedPageID == activePage?.pageID
        {
            restoreSelectionAfterAttachment(
                in: retainedWebView,
                pageID: retainedPageID
            )
        }
        if let warmResumeToken {
            scheduleAfterAttachment {
                warmResumeSignposter?.end(warmResumeToken, outcome: .success)
            }
        }
        if shortcutPresentationMeasurement?.retention == .warm {
            switch state {
            case .active, .suspended:
                finishShortcutPresentationMeasurement(outcome: .success)
            case .offline, .failed:
                finishShortcutPresentationMeasurement(outcome: .failure)
            case .unloaded, .loading:
                break
            }
        }
    }

    func panelDidHide() {
        finishShortcutPresentationMeasurement(outcome: .cancelled)
        lifecycleController.panelDidHide()
        captureSelectionAndSuspendIfNeeded()
    }

    func beginShortcutPresentationMeasurement(
        signposter: any PerformanceSignposting,
        token: PerformanceIntervalToken?,
        retention: WebViewRetention
    ) {
        finishShortcutPresentationMeasurement(outcome: .cancelled)
        shortcutPresentationMeasurement = (signposter, token, retention)
    }

    private func load(
        _ url: URL,
        pageID: String? = nil,
        isDurableRestoration: Bool = false
    ) {
        invalidateEditorSelection()
        webContentRecoveryState = .ready
        pageStateRestoration.recordLoad(
            url: url,
            pageID: pageID,
            isDurableRestoration: isDurableRestoration
        )
        loadedPageID = pageID
        loadedRequestURL = url
        lifecycleController.setState(.loading)
        let webView = ensureWebView()
        beginNavigationRequestMeasurement()
        loadRequest(webView, URLRequest(url: url))
    }

    func reload() {
        guard let activePage else {
            return
        }

        cancelBrowserLogin(resetState: true)
        invalidateEditorSelection()
        webContentRecoveryState = .ready
        revealTopControls()
        guard panelIsVisible else {
            suspendWebViewIfNeeded()
            return
        }
        if let webView {
            lifecycleController.setState(.loading)
            beginNavigationRequestMeasurement()
            webView.reload()
        } else {
            restoreOrLoad(page: activePage)
        }
    }

    func openInBrowser() {
        guard let activePage else {
            return
        }

        openURL(activePage.canonicalURL)
    }

    func continueLoginInBrowser() {
        guard browserLoginState == .loginRequired || isBrowserLoginFailure,
              let webView,
              NotionBrowserHandoffRoute.isLoginURL(browserLoginCurrentURL(webView)),
              let anchor = browserLoginPresentationAnchor(webView),
              let pageID = activePage?.pageID
        else {
            if browserLoginState != .openingBrowser && browserLoginState != .redeeming {
                browserLoginState = .failed(
                    "Browser sign-in could not open. Continue with email or SSO below."
                )
            }
            return
        }

        browserLoginAttemptGeneration &+= 1
        let generation = browserLoginAttemptGeneration
        browserLoginPageID = pageID
        browserLoginRestoringPageID = nil
        browserLoginState = .openingBrowser
        let authenticationSession = browserAuthenticationSessionFactory(
            NotionBrowserHandoffRoute.startURL,
            NotionBrowserHandoffRoute.callbackScheme,
            anchor
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.completeBrowserAuthentication(
                    result,
                    generation: generation,
                    pageID: pageID
                )
            }
        }
        browserAuthenticationSession = authenticationSession
        guard authenticationSession.start() else {
            browserAuthenticationSession = nil
            browserLoginState = .failed(
                "Browser sign-in could not open. Continue with email or SSO below."
            )
            return
        }
    }

    func performBrowserLoginAction() {
        switch browserLoginState {
        case .restorationFailed:
            guard let activePage else { return }
            cancelBrowserLogin(resetState: true)
            load(activePage.canonicalURL, pageID: activePage.pageID)
        case .loginRequired, .failed:
            continueLoginInBrowser()
        case .idle, .openingBrowser, .redeeming:
            break
        }
    }

    func browserLoginRouteDidChange(to url: URL?) {
        guard NotionBrowserHandoffRoute.isLoginURL(url) else {
            if browserLoginRestoringPageID == nil, browserLoginState != .idle {
                cancelBrowserLogin(resetState: true)
            }
            return
        }

        switch browserLoginState {
        case .openingBrowser, .redeeming, .failed, .restorationFailed:
            break
        case .idle, .loginRequired:
            browserLoginState = .loginRequired
        }
    }

    private var isBrowserLoginFailure: Bool {
        if case .failed = browserLoginState {
            return true
        }
        return false
    }

    private func completeBrowserAuthentication(
        _ result: NotionBrowserAuthenticationResult,
        generation: UInt,
        pageID: String
    ) {
        guard generation == browserLoginAttemptGeneration,
              browserLoginPageID == pageID,
              activePage?.pageID == pageID,
              browserLoginState == .openingBrowser
        else {
            return
        }
        browserAuthenticationSession = nil

        switch result {
        case .cancelled:
            browserLoginState = .loginRequired
        case .failed:
            failBrowserLogin(
                "Browser sign-in did not finish. Continue with email or SSO below."
            )
        case let .callback(callbackURL):
            guard let code = NotionBrowserHandoffRoute.code(from: callbackURL),
                  let webView,
                  isCurrent(webView),
                  NotionBrowserHandoffRoute.isLoginURL(browserLoginCurrentURL(webView))
            else {
                failBrowserLogin(
                    "Notion returned an invalid sign-in handoff. Continue with email or SSO below."
                )
                return
            }
            redeemBrowserHandoff(
                code,
                in: webView,
                generation: generation,
                pageID: pageID
            )
        }
    }

    private func redeemBrowserHandoff(
        _ code: String,
        in webView: WKWebView,
        generation: UInt,
        pageID: String
    ) {
        browserLoginState = .redeeming
        browserLoginTimeoutCancellable = scheduleBrowserLoginTimeout(15) {
            [weak self, weak webView] in
            guard let self,
                  let webView,
                  self.browserLoginState == .redeeming
            else {
                return
            }
            if NotionBrowserHandoffRoute.isLoginURL(
                self.browserLoginCurrentURL(webView)
            ) {
                self.failBrowserLogin(
                    "Notion did not finish browser sign-in. Continue with email or SSO below."
                )
            } else {
                self.failBrowserLoginRestoration(
                    "Notion signed in, but the saved page did not finish loading."
                )
            }
        }
        let redemptionCancellable = browserHandoffRedeemer(
            webView,
            code
        ) { [weak self, weak webView] result in
            guard let self,
                  let webView,
                  generation == self.browserLoginAttemptGeneration,
                  self.browserLoginPageID == pageID,
                  self.activePage?.pageID == pageID,
                  self.isCurrent(webView),
                  self.browserLoginState == .redeeming,
                  NotionBrowserHandoffRoute.isLoginURL(
                    self.browserLoginCurrentURL(webView)
                  )
            else {
                return
            }
            self.browserHandoffRedemptionCancellable = nil

            guard case .success(true) = result, let activePage = self.activePage else {
                self.failBrowserLogin(
                    "Browser sign-in is unavailable. Continue with email or SSO below."
                )
                return
            }

            self.browserLoginRestoringPageID = pageID
            self.load(activePage.canonicalURL, pageID: pageID)
        }
        guard browserLoginState == .redeeming else {
            redemptionCancellable.cancel()
            return
        }
        browserHandoffRedemptionCancellable = redemptionCancellable
    }

    func finishBrowserLoginRestorationIfNeeded(at url: URL?) {
        guard let pageID = browserLoginRestoringPageID,
              let url
        else {
            return
        }
        guard let restoredPage = try? NotionPageReference(validating: url),
              restoredPage.pageID == pageID
        else {
            if NotionBrowserHandoffRoute.isLoginURL(url) {
                failBrowserLogin(
                    "Notion did not accept browser sign-in. Continue with email or SSO below."
                )
            }
            return
        }
        browserLoginTimeoutCancellable?.cancel()
        browserLoginTimeoutCancellable = nil
        browserLoginState = .idle
        browserLoginPageID = nil
        browserLoginRestoringPageID = nil
    }

    private func cancelBrowserLogin(resetState: Bool) {
        browserLoginAttemptGeneration &+= 1
        browserAuthenticationSession?.cancel()
        browserAuthenticationSession = nil
        browserHandoffRedemptionCancellable?.cancel()
        browserHandoffRedemptionCancellable = nil
        browserLoginTimeoutCancellable?.cancel()
        browserLoginTimeoutCancellable = nil
        browserLoginPageID = nil
        browserLoginRestoringPageID = nil
        if resetState {
            browserLoginState = .idle
        }
    }

    private func failBrowserLogin(_ message: String) {
        browserHandoffRedemptionCancellable?.cancel()
        browserHandoffRedemptionCancellable = nil
        browserLoginTimeoutCancellable?.cancel()
        browserLoginTimeoutCancellable = nil
        browserLoginRestoringPageID = nil
        browserLoginState = .failed(message)
    }

    private func failBrowserLoginRestoration(_ message: String) {
        browserHandoffRedemptionCancellable?.cancel()
        browserHandoffRedemptionCancellable = nil
        browserLoginTimeoutCancellable?.cancel()
        browserLoginTimeoutCancellable = nil
        browserLoginRestoringPageID = nil
        browserLoginState = .restorationFailed(message)
    }

    func handleEditorActivity(_ activity: NotionEditorActivity) {
        let isTyping = activity == .typingStarted
        guard isTypingInPage != isTyping else { return }
        isTypingInPage = isTyping
        lifecycleController.setEvictionProtected(isTyping)
    }

    func handleScrollSnapshot(_ snapshot: NotionScrollSnapshot) {
        pageStateRestoration.recordScroll(snapshot, pageID: loadedPageID)
    }

    func handleScrollSnapshot(
        _ snapshot: NotionScrollSnapshot,
        from webView: WKWebView?,
        generation: UInt
    ) {
        guard let webView, isCurrent(webView, generation: generation) else {
            return
        }
        handleScrollSnapshot(snapshot)
    }

    func handleUsefulContent(
        _ message: NotionUsefulContentMessage,
        from webView: WKWebView?,
        generation: UInt
    ) {
        guard let webView, isCurrent(webView, generation: generation) else {
            return
        }
        guard completedUsefulContentDocumentID != message.documentID else { return }
        let measurementGeneration = usefulContentMeasurementGeneration
        usefulContentDocumentIdentifierReader(webView) { [weak self, weak webView] documentID in
            guard let self,
                  let webView,
                  self.isCurrent(webView, generation: generation),
                  self.usefulContentMeasurementGeneration == measurementGeneration,
                  self.completedUsefulContentDocumentID != message.documentID,
                  documentID == message.documentID
            else {
                return
            }
            self.processUsefulContentMessage(message, from: webView)
        }
    }

    private func processUsefulContentMessage(
        _ message: NotionUsefulContentMessage,
        from webView: WKWebView
    ) {
        guard completedUsefulContentDocumentID != message.documentID else { return }
        switch message.state {
        case .ready:
            guard finishedNavigationMatchesLoadedPage(
                at: webView.url ?? loadedRequestURL
            ) else {
                pendingUsefulContentMessage = message
                return
            }
            completedUsefulContentDocumentID = message.documentID
            finishUsefulContentMeasurements(outcome: .success)
        case .timedOut:
            completedUsefulContentDocumentID = message.documentID
            finishUsefulContentMeasurements(outcome: .failure)
        }
    }

    private func retryPendingUsefulContentMessage() {
        guard let webView, let message = pendingUsefulContentMessage else { return }
        processUsefulContentMessage(message, from: webView)
    }

    private func invalidateUsefulContentDocumentTracking() {
        usefulContentMeasurementGeneration &+= 1
        pendingUsefulContentMessage = nil
    }

    func evictInteractionSnapshots(retaining pageIDs: Set<String>) {
        pageStateRestoration.evictInteractionStates(retaining: pageIDs)
    }

    func handleEditorActivity(
        _ activity: NotionEditorActivity,
        from webView: WKWebView?
    ) {
        handleEditorActivity(
            activity,
            from: webView,
            generation: scriptMessageCoordinator.generation
        )
    }

    func handleEditorActivity(
        _ activity: NotionEditorActivity,
        from webView: WKWebView?,
        generation: UInt
    ) {
        guard let webView, isCurrent(webView, generation: generation) else {
            return
        }
        handleEditorActivity(activity)
    }

    func revealTopControls() {
        handleEditorActivity(.editingEnded)
    }

    func handleMemoryPressure() {
        if lifecycleController.requestEvictionIfEligible() {
            pageStateRestoration.removeAllInteractionStates()
        }
    }

    func evictWarmWebView() {
        _ = lifecycleController.requestEvictionIfEligible()
    }

    private func evictWarmWebView(afterLifecycleDecision: Bool) {
        guard afterLifecycleDecision, let webView else { return }
        let evictionToken = performanceSignposter?.begin(.webViewEviction)

        if let activePage {
            captureAndTearDown(webView, page: activePage)
        } else {
            _ = retire(webView)
        }
        lifecycleController.didEvictWebView()
        performanceSignposter?.end(
            evictionToken,
            outcome: .success,
            metadata: PerformanceMetadata(
                cacheEntryCount: pageStateRestoration.interactionStateCount
            )
        )
    }

    @discardableResult
    private func retire(_ webView: WKWebView) -> Bool {
        guard isCurrent(webView) else {
            return false
        }

        finishNavigationRequestMeasurement(outcome: .cancelled)
        finishUsefulContentMeasurements(outcome: .cancelled)

        popupCoordinator.close()
        lifecycleController.cancelWarmRetention()
        self.webView = nil
        loadedPageID = nil
        loadedRequestURL = nil
        if let urlObservation {
            invalidateURLObservation(urlObservation)
            self.urlObservation = nil
        }
        scriptMessageCoordinator.remove(from: webView.configuration.userContentController)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        stopLoading(webView)
        webView.removeFromSuperview()
        return true
    }

    private func isCurrent(_ webView: WKWebView, generation: UInt? = nil) -> Bool {
        guard self.webView === webView else {
            return false
        }
        return generation == nil || generation == scriptMessageCoordinator.generation
    }

    private func captureSelectionAndSuspendIfNeeded() {
        invalidateEditorSelection()
        let generation = selectionCaptureGeneration
        guard let webView,
              state == .active,
              let pageID = activePage?.pageID,
              loadedPageID == pageID,
              Self.isTrustedSelectionContext(webView, pageID: pageID)
        else {
            suspendWebViewIfNeeded()
            return
        }

        selectionEvaluator(webView, .capture) { [weak self, weak webView] result in
            guard let self,
                  let webView,
                  self.selectionCaptureGeneration == generation,
                  !self.panelIsVisible,
                  self.webView === webView,
                  self.activePage?.pageID == pageID,
                  self.loadedPageID == pageID
            else {
                return
            }

            if case let .success(value) = result,
               let snapshot = NotionEditorSelectionSnapshot(javaScriptValue: value)
            {
                self.savedEditorSelection = (pageID, snapshot)
            }
            self.suspendWebViewIfNeeded()
        }
    }

    private func invalidateEditorSelection() {
        selectionCaptureGeneration &+= 1
        savedEditorSelection = nil
        onQuickCopyTargetInvalidated?()
    }

    private func invalidateEditorSelectionAndSuspendIfHidden() {
        invalidateEditorSelection()
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    private func suspendWebViewIfNeeded() {
        guard let webView,
              lifecycleController.suspend(hasWebView: true)
        else {
            revealTopControls()
            return
        }

        revealTopControls()
        endEditing(webView)
        pauseMedia(webView)
        webView.removeFromSuperview()
    }

    private func restoreSelectionAfterAttachment(in webView: WKWebView, pageID: String?) {
        guard let pageID else { return }
        scheduleAfterAttachment { [weak self, weak webView] in
            guard let self,
                  let webView,
                  self.panelIsVisible,
                  self.webView === webView,
                  self.activePage?.pageID == pageID,
                  self.loadedPageID == pageID
            else {
                return
            }

            self.focusWebView(webView)
            let savedSelection = self.savedEditorSelection
            self.savedEditorSelection = nil
            guard savedSelection?.pageID == pageID,
                  let snapshot = savedSelection?.snapshot,
                  Self.isTrustedSelectionContext(webView, pageID: pageID)
            else {
                return
            }
            self.selectionEvaluator(webView, .restore(snapshot)) { _ in }
        }
    }

    private static func isTrustedSelectionContext(_ webView: WKWebView, pageID: String) -> Bool {
        guard WebNavigationDestination.classify(webView.url) == .trustedNotion,
              let url = webView.url,
              let page = try? NotionPageReference(validating: url)
        else {
            return false
        }
        return page.pageID == pageID
    }

    private func restoreOrLoad(page: NotionPageReference) {
        invalidateEditorSelection()
        if restorationToken != nil {
            performanceSignposter?.end(restorationToken, outcome: .cancelled)
        }
        restorationToken = performanceSignposter?.begin(.notionSessionRestoration)
        let webView = ensureWebView()
        switch pageStateRestoration.restorationPlan(for: page) {
        case let .interactionState(interactionState):
            finishNavigationUsefulContentMeasurements(outcome: .cancelled)
            interactionStateRestoreToUsefulContentToken = performanceSignposter?.begin(
                .interactionStateRestoreToUsefulContent
            )
            interactionStateWriter(webView, interactionState)
            loadedPageID = page.pageID
            lifecycleController.setState(.loading)
        case let .load(restorationURL, isDurableRestoration):
            load(
                restorationURL,
                pageID: page.pageID,
                isDurableRestoration: isDurableRestoration
            )
        }
    }

    private func beginNavigationRequestMeasurement(
        preservingUsefulContentContext: Bool = false
    ) {
        invalidateUsefulContentDocumentTracking()
        finishNavigationRequestMeasurement(outcome: .cancelled)
        if preservingUsefulContentContext {
            if commitToUsefulContentToken != nil {
                performanceSignposter?.end(commitToUsefulContentToken, outcome: .cancelled)
                commitToUsefulContentToken = nil
            }
        } else {
            finishNavigationUsefulContentMeasurements(outcome: .cancelled)
        }
        navigationRequestToCommitToken = performanceSignposter?.begin(
            .navigationRequestToCommit
        )
    }

    private func finishNavigationRequestMeasurement(outcome: PerformanceOutcome) {
        guard navigationRequestToCommitToken != nil else { return }
        performanceSignposter?.end(navigationRequestToCommitToken, outcome: outcome)
        navigationRequestToCommitToken = nil
    }

    private func finishNavigationUsefulContentMeasurements(
        outcome: PerformanceOutcome
    ) {
        if commitToUsefulContentToken != nil {
            performanceSignposter?.end(commitToUsefulContentToken, outcome: outcome)
            commitToUsefulContentToken = nil
        }
        if interactionStateRestoreToUsefulContentToken != nil {
            performanceSignposter?.end(
                interactionStateRestoreToUsefulContentToken,
                outcome: outcome
            )
            interactionStateRestoreToUsefulContentToken = nil
        }
        if rendererRecoveryToUsefulContentToken != nil {
            performanceSignposter?.end(
                rendererRecoveryToUsefulContentToken,
                outcome: outcome
            )
            rendererRecoveryToUsefulContentToken = nil
        }
    }

    private func finishUsefulContentMeasurements(outcome: PerformanceOutcome) {
        finishNavigationUsefulContentMeasurements(outcome: outcome)
        finishShortcutPresentationMeasurement(outcome: outcome)
        invalidateUsefulContentDocumentTracking()
    }

    private func captureAndTearDown(
        _ webView: WKWebView,
        page: NotionPageReference
    ) {
        guard isCurrent(webView) else { return }
        guard webContentRecoveryState == .ready else {
            _ = retire(webView)
            return
        }
        endEditing(webView)
        if let restoration = pageStateRestoration.capture(
            page: page,
            currentURL: webView.url,
            interactionState: interactionStateReader(webView)
        ) {
            onRestorationCaptured?(restoration)
        }
        _ = retire(webView)
    }

    private func publishNavigationState(_ navigationState: NotionWebSessionState) {
        lifecycleController.publishNavigationState(navigationState)
    }

    private func installMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.preferences.inactiveSchedulingPolicy = .suspend
        return ExternalDropActivatingWebView(frame: .zero, configuration: configuration)
    }

    static func restoreScroll(
        in webView: WKWebView,
        restoration: DurablePageRestoration,
        callAsyncJavaScript: @escaping NotionWebScrollJavaScriptCaller = {
            webView,
            script,
            arguments in
            try await webView.callAsyncJavaScript(
                script,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
        }
    ) {
        Task { @MainActor [weak webView] in
            guard let webView else { return }
            let script = """
                return await new Promise((resolve) => {
                  const deadline = performance.now() + timeoutMilliseconds;
                  const apply = () => {
                    const root = document.scrollingElement || document.documentElement;
                    if (root) {
                      const maximum = Math.max(0, root.scrollHeight - window.innerHeight);
                      const target = maximum > 0
                        ? Math.max(scrollY, maximum * scrollProgress)
                        : scrollY;
                      window.scrollTo(scrollX, target);
                      if (Math.abs(window.scrollY - target) < tolerancePixels || maximum === 0) {
                        resolve(true);
                        return;
                      }
                    }
                    if (performance.now() >= deadline) {
                      resolve(false);
                      return;
                    }
                    window.setTimeout(
                      () => window.requestAnimationFrame(apply),
                      retryDelayMilliseconds
                    );
                  };
                  apply();
                });
                """
            _ = try? await callAsyncJavaScript(
                webView,
                script,
                [
                    "scrollX": restoration.scrollX,
                    "scrollY": restoration.scrollY,
                    "scrollProgress": restoration.scrollProgress,
                    "timeoutMilliseconds": 2_000,
                    "tolerancePixels": 4,
                    "retryDelayMilliseconds": 100,
                ]
            )
        }
    }
}

extension NotionWebSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard isCurrent(webView) else {
            return .cancel
        }
        let context: NotionWebNavigationContext
        if let targetFrame = navigationAction.targetFrame {
            context = targetFrame.isMainFrame ? .mainFrame : .subframe
        } else {
            context = .newWindow
        }
        return navigationPolicy(
            for: navigationAction.request.url,
            context: context
        )
    }

    func navigationPolicy(
        for url: URL?,
        context: NotionWebNavigationContext
    ) -> WKNavigationActionPolicy {
        switch navigationDecisionPolicy.actionDecision(
            for: url,
            context: context
        ) {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case let .openExternally(url):
            openURL(url)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard isCurrent(webView) else { return }
        if case .failed = webContentRecoveryState { return }
        invalidateUsefulContentDocumentTracking()
        if navigationRequestToCommitToken == nil {
            beginNavigationRequestMeasurement(preservingUsefulContentContext: true)
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(.loading)
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard isCurrent(webView) else { return }
        finishNavigationRequestMeasurement(outcome: .success)
        if commitToUsefulContentToken != nil {
            performanceSignposter?.end(commitToUsefulContentToken, outcome: .cancelled)
        }
        commitToUsefulContentToken = performanceSignposter?.begin(.commitToUsefulContent)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isCurrent(webView) else { return }
        switch webContentRecoveryState {
        case let .attempting(pageID):
            guard pageID == activePage?.pageID, pageID == loadedPageID else { return }
            webContentRecoveryState = .ready
        case .failed:
            return
        case .ready:
            break
        }
        let finishedLoadedPage = finishedNavigationMatchesLoadedPage(
            at: webView.url ?? loadedRequestURL
        )
        if finishedLoadedPage {
            pageStateRestoration.navigationDidFinish()
        }
        invalidateEditorSelection()
        publishNavigationState(.active)
        if restorationToken != nil {
            performanceSignposter?.end(restorationToken, outcome: .success)
        }
        restorationToken = nil
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
        adoptResolvedPage(
            at: webView.url,
            from: webView,
            generation: scriptMessageCoordinator.generation
        )
        browserLoginRouteDidChange(to: webView.url)
        finishBrowserLoginRestorationIfNeeded(at: webView.url)
        retryPendingUsefulContentMessage()
        if pendingUsefulContentMessage != nil {
            finishUsefulContentMeasurements(outcome: .failure)
        }
        if finishedLoadedPage,
           let restoration = pageStateRestoration.takePendingScrollRestoration(
            for: loadedPageID
           )
        {
            scrollRestorer(webView, restoration)
        }
    }

    private func finishShortcutPresentationMeasurement(outcome: PerformanceOutcome) {
        guard let measurement = shortcutPresentationMeasurement else { return }
        shortcutPresentationMeasurement = nil
        measurement.signposter.end(
            measurement.token,
            outcome: outcome,
            metadata: PerformanceMetadata(webViewRetention: measurement.retention)
        )
    }

    func finishedNavigationMatchesLoadedPage(at url: URL?) -> Bool {
        guard let loadedPageID,
              let url,
              let page = try? NotionPageReference(validating: url)
        else {
            return false
        }
        return page.pageID == loadedPageID
    }

    func adoptResolvedPage(at url: URL?) {
        guard let webView else { return }
        adoptResolvedPage(
            at: url,
            from: webView,
            generation: scriptMessageCoordinator.generation
        )
    }

    func adoptResolvedPage(at url: URL?, from webView: WKWebView) {
        adoptResolvedPage(
            at: url,
            from: webView,
            generation: scriptMessageCoordinator.generation
        )
    }

    private func adoptResolvedPage(
        at url: URL?,
        from webView: WKWebView,
        generation: UInt
    ) {
        guard let url,
              isCurrent(webView, generation: generation),
              let resolvedPage = try? NotionPageReference(validating: url),
              webView.url == url,
              loadedPageID == activePage?.pageID,
              resolvedPage.pageID != activePage?.pageID
        else {
            return
        }

        revealTopControls()
        invalidateEditorSelection()
        activePage = resolvedPage
        loadedPageID = resolvedPage.pageID
        loadedRequestURL = url
        pageStateRestoration.recordResolvedPage(resolvedPage, at: url)
        if case .attempting = webContentRecoveryState {
            // A trusted Notion redirect can resolve the recovery navigation to a
            // different document before didFinish. Follow the adopted document so
            // completion cannot leave recovery stuck, but discard the old page's
            // scroll fallback and keep the same single-attempt budget.
            webContentRecoveryState = .attempting(pageID: resolvedPage.pageID)
            pageStateRestoration.discardPendingScrollRestoration()
        }
        onPageResolved?(resolvedPage)
        retryPendingUsefulContentMessage()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard isCurrent(webView) else { return }
        guard !isCancellation(error) else {
            finishNavigationRequestMeasurement(outcome: .cancelled)
            finishUsefulContentMeasurements(outcome: .cancelled)
            if restorationToken != nil {
                performanceSignposter?.end(restorationToken, outcome: .cancelled)
                restorationToken = nil
            }
            invalidateEditorSelectionAndSuspendIfHidden()
            return
        }
        if fallBackFromFailedDurableRestoration() {
            return
        }
        markWebContentRecoveryFailedIfNeeded()
        if browserLoginRestoringPageID != nil {
            failBrowserLoginRestoration(
                "Notion signed in, but the saved page did not reload."
            )
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(navigationFailureState(for: error))
        finishNavigationRequestMeasurement(outcome: .failure)
        finishUsefulContentMeasurements(outcome: .failure)
        if restorationToken != nil {
            performanceSignposter?.end(restorationToken, outcome: .failure)
        }
        restorationToken = nil
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isCurrent(webView) else { return }
        guard !isCancellation(error) else {
            finishNavigationRequestMeasurement(outcome: .cancelled)
            finishUsefulContentMeasurements(outcome: .cancelled)
            if restorationToken != nil {
                performanceSignposter?.end(restorationToken, outcome: .cancelled)
                restorationToken = nil
            }
            invalidateEditorSelectionAndSuspendIfHidden()
            return
        }
        if fallBackFromFailedDurableRestoration() {
            return
        }
        markWebContentRecoveryFailedIfNeeded()
        if browserLoginRestoringPageID != nil {
            failBrowserLoginRestoration(
                "Notion signed in, but the saved page did not reload."
            )
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(navigationFailureState(for: error))
        finishNavigationRequestMeasurement(outcome: .failure)
        finishUsefulContentMeasurements(outcome: .failure)
        if restorationToken != nil {
            performanceSignposter?.end(restorationToken, outcome: .failure)
        }
        restorationToken = nil
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        navigationDecisionPolicy.failureDecision(for: error) == .cancelled
    }

    private func navigationFailureState(for error: Error) -> NotionWebSessionState {
        switch navigationDecisionPolicy.failureDecision(for: error) {
        case .cancelled:
            return .loading
        case .offline:
            return .offline
        case let .failed(message):
            return .failed(message)
        }
    }

    static func isOfflineNavigationError(_ error: Error) -> Bool {
        NotionWebNavigationPolicy().failureDecision(for: error) == .offline
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isCurrent(webView) else { return }
        popupCoordinator.close()
        finishNavigationRequestMeasurement(outcome: .failure)
        finishUsefulContentMeasurements(outcome: .failure)

        if restorationToken != nil {
            performanceSignposter?.end(restorationToken, outcome: .failure)
            restorationToken = nil
        }

        revealTopControls()
        invalidateEditorSelection()
        refreshDOMBridges(afterTerminationOf: webView)
        let page = activePage
        pageStateRestoration.rendererDidTerminate(
            page: page,
            loadedPageID: loadedPageID
        )
        guard let page else {
            publishNavigationState(.failed("Notion couldn't reload after its web content stopped."))
            return
        }

        switch webContentRecoveryState {
        case .attempting(pageID: page.pageID), .failed(pageID: page.pageID):
            webContentRecoveryState = .failed(pageID: page.pageID)
            pageStateRestoration.discardPendingScrollRestoration()
            publishNavigationState(.failed("Notion couldn't reload after its web content stopped."))
            return
        case .ready, .attempting, .failed:
            webContentRecoveryState = .attempting(pageID: page.pageID)
        }

        loadedPageID = page.pageID
        loadedRequestURL = page.canonicalURL
        publishNavigationState(.loading)
        rendererRecoveryToUsefulContentToken = performanceSignposter?.begin(
            .rendererRecoveryToUsefulContent
        )
        beginNavigationRequestMeasurement(preservingUsefulContentContext: true)
        loadRequest(webView, URLRequest(url: page.canonicalURL))
    }

    private func markWebContentRecoveryFailedIfNeeded() {
        guard case let .attempting(pageID) = webContentRecoveryState else { return }
        webContentRecoveryState = .failed(pageID: pageID)
        pageStateRestoration.discardPendingScrollRestoration()
    }

    private func fallBackFromFailedDurableRestoration() -> Bool {
        guard let activePage,
              let canonicalURL = pageStateRestoration
                .canonicalFallbackAfterFailedDurableRestoration(for: activePage)
        else {
            return false
        }
        load(canonicalURL, pageID: activePage.pageID)
        return true
    }
}

extension NotionWebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard isCurrent(webView) else { return nil }
        return handleNewWindowRequest(
            navigationAction.request,
            configuration: configuration,
            in: webView
        )
    }

    func handleNewWindowRequest(
        _ request: URLRequest,
        configuration: WKWebViewConfiguration,
        in webView: WKWebView
    ) -> WKWebView? {
        guard isCurrent(webView) else { return nil }
        switch navigationDecisionPolicy.newWindowDecision(for: request) {
        case .createPopup:
            return popupCoordinator.present(using: configuration)
        case let .openExternally(url):
            openURL(url)
        case .ignore:
            break
        }
        return nil
    }
}
