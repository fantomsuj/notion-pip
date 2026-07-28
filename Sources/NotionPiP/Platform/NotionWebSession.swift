import Combine
import AppKit
import WebKit

typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void
typealias NotionWebViewFactory = @MainActor () -> WKWebView
typealias NotionWebEvictionScheduler = @MainActor (
    TimeInterval,
    @escaping @MainActor () -> Void
) -> AnyCancellable
typealias NotionWebAttachmentScheduler = @MainActor (
    @escaping @MainActor () -> Void
) -> Void

enum NotionEditorActivity: String, Equatable {
    case typingStarted
    case editingEnded
}

enum NotionEditorActivityBridge {
    static let handlerName = "notionPiPChromeActivity"

    static func activity(
        from body: Any,
        isMainFrame: Bool,
        scheme: String,
        host: String
    ) -> NotionEditorActivity? {
        guard isMainFrame,
              scheme.lowercased() == "https",
              ["app.notion.com", "notion.so", "www.notion.so"].contains(host.lowercased()),
              let rawActivity = body as? String
        else {
            return nil
        }

        return NotionEditorActivity(rawValue: rawActivity)
    }
}

@MainActor
private protocol NotionEditorActivityHandling: AnyObject {
    func handleEditorActivity(_ activity: NotionEditorActivity)
}

@MainActor
private final class WeakNotionEditorActivityMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionEditorActivityHandling)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let activity = NotionEditorActivityBridge.activity(
            from: message.body,
            isMainFrame: message.frameInfo.isMainFrame,
            scheme: message.frameInfo.securityOrigin.protocol,
            host: message.frameInfo.securityOrigin.host
        ) else {
            return
        }

        delegate?.handleEditorActivity(activity)
    }
}

@MainActor
protocol NotionPageLoading: AnyObject {
    func activate(page: NotionPageReference)
    func reloadPinnedPage(_ page: NotionPageReference)
    func reselect(page: NotionPageReference)
    func panelDidShow()
    func panelDidHide()
}

extension NotionPageLoading {
    func reselect(page: NotionPageReference) {}
    func panelDidShow() {}
    func panelDidHide() {}
}

@MainActor
enum NotionWebSessionState: Equatable {
    case unloaded
    case loading
    case active
    case suspended
    case failed(String)
}

@MainActor
final class NotionWebSession: NSObject, NotionPageLoading, ObservableObject,
    NotionEditorActivityHandling
{
    static let warmRetentionInterval: TimeInterval = 60

    @Published private(set) var webView: WKWebView?
    @Published private(set) var state: NotionWebSessionState = .unloaded
    @Published private(set) var isTypingInPage = false
    private(set) var activePage: NotionPageReference?
    var onPageResolved: (@MainActor (NotionPageReference) -> Void)?
    private let openURL: @MainActor (URL) -> Void
    private let loadRequest: NotionWebRequestLoader
    private let webViewFactory: NotionWebViewFactory
    private let scheduleEviction: NotionWebEvictionScheduler
    private let pauseMedia: @MainActor (WKWebView) -> Void
    private let stopLoading: @MainActor (WKWebView) -> Void
    private let interactionStateReader: @MainActor (WKWebView) -> Any?
    private let interactionStateWriter: @MainActor (WKWebView, Any) -> Void
    private let selectionEvaluator: NotionEditorSelectionEvaluator
    private let scheduleAfterAttachment: NotionWebAttachmentScheduler
    private let focusWebView: @MainActor (WKWebView) -> Void
    private let editorActivityHandler: WeakNotionEditorActivityMessageHandler
    private var urlObservation: NSKeyValueObservation?
    private var evictionCancellable: AnyCancellable?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    @Published private var panelIsVisible = true
    private var stateBeforeSuspension: NotionWebSessionState = .unloaded
    private var loadedPageID: String?
    private var savedURL: URL?
    private var savedURLPageID: String?
    private var savedInteractionState: Any?
    private var savedInteractionPageID: String?
    private var selectionCaptureGeneration = 0
    private var savedEditorSelection: (
        pageID: String,
        snapshot: NotionEditorSelectionSnapshot
    )?

    var shouldHostWebView: Bool {
        panelIsVisible
            && state != .suspended
            && webView != nil
    }

    init(
        webView: WKWebView? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        loadRequest: @escaping NotionWebRequestLoader = { webView, request in
            webView.load(request)
        },
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
        }
    ) {
        let activityHandler = WeakNotionEditorActivityMessageHandler()
        self.webView = nil
        self.openURL = openURL
        self.loadRequest = loadRequest
        self.webViewFactory = webViewFactory
        self.scheduleEviction = scheduleEviction
        self.pauseMedia = pauseMedia
        self.stopLoading = stopLoading
        self.interactionStateReader = interactionStateReader
        self.interactionStateWriter = interactionStateWriter
        self.selectionEvaluator = selectionEvaluator
        self.scheduleAfterAttachment = scheduleAfterAttachment
        self.focusWebView = focusWebView
        editorActivityHandler = activityHandler
        super.init()
        if let webView {
            configure(webView)
        }
        installMemoryPressureSource()
    }

    private func configure(_ webView: WKWebView) {
        self.webView = webView
        Self.installEditorActivityBridge(
            in: webView.configuration.userContentController,
            handler: editorActivityHandler
        )
        editorActivityHandler.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.adoptResolvedPage(at: webView.url)
            }
        }
    }

    @discardableResult
    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }
        let webView = webViewFactory()
        configure(webView)
        return webView
    }

    func activate(page: NotionPageReference) {
        guard activePage?.canonicalURL != page.canonicalURL else {
            return
        }

        prepare(page: page)
        guard panelIsVisible, state != .suspended else {
            if !panelIsVisible {
                suspendWebViewIfNeeded()
            }
            return
        }
        load(page.canonicalURL, pageID: page.pageID)
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        prepare(page: page)
        load(page.canonicalURL, pageID: page.pageID)
    }

    private func prepare(page: NotionPageReference) {
        let selectedRouteChanged = activePage?.canonicalURL != page.canonicalURL
        activePage = page
        revealTopControls()
        savedURL = page.canonicalURL
        savedURLPageID = page.pageID
        if selectedRouteChanged {
            savedInteractionState = nil
            savedInteractionPageID = nil
            invalidateEditorSelection()
        }
    }

    func panelDidShow() {
        let wasHidden = !panelIsVisible
        let retainedWebView = webView
        let retainedPageID = loadedPageID
        selectionCaptureGeneration &+= 1
        panelIsVisible = true
        if state == .suspended {
            resumeSuspendedWebView()
        } else if webView == nil, let activePage {
            restoreOrLoad(page: activePage)
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
    }

    func panelDidHide() {
        panelIsVisible = false
        captureSelectionAndSuspendIfNeeded()
    }

    private func load(_ url: URL, pageID: String? = nil) {
        invalidateEditorSelection()
        savedURL = url
        savedURLPageID = pageID
        loadedPageID = pageID
        state = .loading
        loadRequest(ensureWebView(), URLRequest(url: url))
    }

    func reload() {
        guard let activePage else {
            return
        }

        invalidateEditorSelection()
        revealTopControls()
        guard panelIsVisible else {
            suspendWebViewIfNeeded()
            return
        }
        if let webView {
            state = .loading
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

    func handleEditorActivity(_ activity: NotionEditorActivity) {
        let isTyping = activity == .typingStarted
        guard isTypingInPage != isTyping else { return }
        isTypingInPage = isTyping
    }

    func revealTopControls() {
        handleEditorActivity(.editingEnded)
    }

    func handleMemoryPressure() {
        guard state == .suspended,
              !isTypingInPage,
              !panelIsVisible
        else {
            return
        }
        evictWarmWebView()
    }

    func evictWarmWebView() {
        guard state == .suspended,
              !isTypingInPage,
              !panelIsVisible,
              let webView
        else {
            return
        }

        evictionCancellable?.cancel()
        evictionCancellable = nil
        invalidateEditorSelection()
        if loadedPageID == activePage?.pageID {
            savedURL = webView.url ?? savedURL ?? activePage?.canonicalURL
            savedURLPageID = loadedPageID
        }
        savedInteractionState = interactionStateReader(webView)
        savedInteractionPageID = loadedPageID
        stopLoading(webView)
        urlObservation?.invalidate()
        urlObservation = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: NotionEditorActivityBridge.handlerName,
            contentWorld: .page
        )
        webView.configuration.userContentController.removeAllUserScripts()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        self.webView = nil
        state = .unloaded
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
    }

    private func invalidateEditorSelectionAndSuspendIfHidden() {
        invalidateEditorSelection()
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    private func suspendWebViewIfNeeded() {
        guard let webView, state != .suspended else {
            revealTopControls()
            return
        }

        stateBeforeSuspension = state
        revealTopControls()
        webView.window?.endEditing(for: webView)
        _ = webView.window?.makeFirstResponder(nil)
        pauseMedia(webView)
        webView.removeFromSuperview()
        state = .suspended
        evictionCancellable?.cancel()
        evictionCancellable = scheduleEviction(Self.warmRetentionInterval) { [weak self] in
            self?.evictWarmWebView()
        }
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

    private func resumeSuspendedWebView() {
        evictionCancellable?.cancel()
        evictionCancellable = nil
        guard let activePage else {
            state = webView == nil ? .unloaded : stateBeforeSuspension
            return
        }
        if webView == nil {
            restoreOrLoad(page: activePage)
        } else if loadedPageID != activePage.pageID {
            load(activePage.canonicalURL, pageID: activePage.pageID)
        } else {
            state = stateBeforeSuspension == .suspended ? .active : stateBeforeSuspension
        }
    }

    private func restoreOrLoad(page: NotionPageReference) {
        invalidateEditorSelection()
        let webView = ensureWebView()
        if let savedInteractionState,
           savedInteractionPageID == page.pageID
        {
            interactionStateWriter(webView, savedInteractionState)
            loadedPageID = page.pageID
            state = .loading
        } else {
            let restorationURL = savedURLPageID == nil || savedURLPageID == page.pageID
                ? savedURL ?? page.canonicalURL
                : page.canonicalURL
            load(restorationURL, pageID: page.pageID)
        }
    }

    private func publishNavigationState(_ navigationState: NotionWebSessionState) {
        if state == .suspended {
            stateBeforeSuspension = navigationState
        } else {
            state = navigationState
        }
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
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private static func installEditorActivityBridge(
        in userContentController: WKUserContentController,
        handler: WeakNotionEditorActivityMessageHandler
    ) {
        userContentController.addUserScript(
            WKUserScript(
                source: editorActivityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.add(
            handler,
            contentWorld: .page,
            name: NotionEditorActivityBridge.handlerName
        )
    }

    private static let editorActivityScript = #"""
        (() => {
          if (window.__notionPiPChromeActivityInstalled) return;
          window.__notionPiPChromeActivityInstalled = true;

          let isTyping = false;

          const editableElement = (node) => {
            const element = node instanceof Element ? node : node?.parentElement;
            if (!element) return null;

            const textControl = element.closest('input, textarea');
            if (textControl && !textControl.disabled && !textControl.readOnly) {
              return textControl;
            }

            const editable = element.closest('[contenteditable]');
            if (!editable || editable.getAttribute('contenteditable') === 'false') {
              return null;
            }
            return editable;
          };

          const postActivity = (activity) => {
            window.webkit?.messageHandlers?.notionPiPChromeActivity?.postMessage(activity);
          };

          const publishTypingStarted = () => {
            isTyping = true;
            postActivity('typingStarted');
          };

          const publishEditingEnded = () => {
            if (!isTyping) return;
            isTyping = false;
            postActivity('editingEnded');
          };

          document.addEventListener('beforeinput', (event) => {
            if (editableElement(event.target)) publishTypingStarted();
          }, true);

          document.addEventListener('pointermove', publishEditingEnded, {
            capture: true,
            passive: true,
          });

          document.addEventListener('focusout', (event) => {
            if (!editableElement(event.target)) return;
            window.setTimeout(() => {
              if (!editableElement(document.activeElement)) publishEditingEnded();
            }, 0);
          }, true);

          document.addEventListener('keydown', (event) => {
            if (event.key === 'Tab' || event.key === 'Escape') publishEditingEnded();
          }, true);
        })();
        """#
}

extension NotionWebSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationPolicy(
            for: navigationAction.request.url,
            targetFrameIsPresent: navigationAction.targetFrame != nil
        )
    }

    func navigationPolicy(
        for url: URL?,
        targetFrameIsPresent: Bool
    ) -> WKNavigationActionPolicy {
        guard targetFrameIsPresent else {
            return .allow
        }

        switch WebNavigationDestination.classify(url) {
        case .trustedNotion:
            return .allow
        case .externalWeb:
            if let url {
                openURL(url)
            }
            return .cancel
        case .unsupported:
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(.loading)
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        invalidateEditorSelection()
        publishNavigationState(.active)
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
        adoptResolvedPage(at: webView.url)
    }

    func adoptResolvedPage(at url: URL?) {
        guard let url,
              let resolvedPage = try? NotionPageReference(validating: url),
              webView?.url == url,
              loadedPageID == activePage?.pageID,
              resolvedPage.pageID != activePage?.pageID
        else {
            return
        }

        revealTopControls()
        invalidateEditorSelection()
        activePage = resolvedPage
        loadedPageID = resolvedPage.pageID
        savedURL = url
        savedURLPageID = resolvedPage.pageID
        onPageResolved?(resolvedPage)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard !isCancellation(error) else {
            invalidateEditorSelectionAndSuspendIfHidden()
            return
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(.failed(error.localizedDescription))
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isCancellation(error) else {
            invalidateEditorSelectionAndSuspendIfHidden()
            return
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(.failed(error.localizedDescription))
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}

extension NotionWebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        handleNewWindowRequest(navigationAction.request, in: webView)
    }

    func handleNewWindowRequest(
        _ request: URLRequest,
        in webView: WKWebView
    ) -> WKWebView? {
        switch WebNavigationDestination.classify(request.url) {
        case .trustedNotion:
            loadRequest(webView, request)
        case .externalWeb:
            if let url = request.url {
                openURL(url)
            }
        case .unsupported:
            break
        }
        return nil
    }
}
