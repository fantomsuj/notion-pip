import Combine
import AppKit
import WebKit

typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void
typealias NotionWebViewFactory = @MainActor () -> WKWebView
typealias NotionWebScrollRestorer = @MainActor (WKWebView, DurablePageRestoration) -> Void
typealias NotionWebEvictionScheduler = @MainActor (
    TimeInterval,
    @escaping @MainActor () -> Void
) -> AnyCancellable

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

struct NotionScrollSnapshot: Equatable, Sendable {
    let x: Double
    let y: Double
    let progress: Double
}

enum NotionScrollBridge {
    static let handlerName = "notionPiPScroll"

    static func snapshot(
        from body: Any,
        isMainFrame: Bool,
        scheme: String,
        host: String
    ) -> NotionScrollSnapshot? {
        guard isMainFrame,
              scheme.lowercased() == "https",
              ["app.notion.com", "notion.so", "www.notion.so"].contains(host.lowercased()),
              let values = body as? [String: Any],
              Set(values.keys) == ["x", "y", "progress"],
              let x = (values["x"] as? NSNumber)?.doubleValue,
              let y = (values["y"] as? NSNumber)?.doubleValue,
              let progress = (values["progress"] as? NSNumber)?.doubleValue,
              x.isFinite,
              y.isFinite,
              progress.isFinite,
              (0 ... 1).contains(progress)
        else {
            return nil
        }
        return NotionScrollSnapshot(x: x, y: y, progress: progress)
    }
}

@MainActor
private protocol NotionEditorActivityHandling: AnyObject {
    func handleEditorActivity(_ activity: NotionEditorActivity)
}

@MainActor
private protocol NotionScrollHandling: AnyObject {
    func handleScrollSnapshot(_ snapshot: NotionScrollSnapshot)
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
private final class WeakNotionScrollMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionScrollHandling)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let snapshot = NotionScrollBridge.snapshot(
            from: message.body,
            isMainFrame: message.frameInfo.isMainFrame,
            scheme: message.frameInfo.securityOrigin.protocol,
            host: message.frameInfo.securityOrigin.host
        ) else {
            return
        }
        delegate?.handleScrollSnapshot(snapshot)
    }
}

@MainActor
protocol NotionPageLoading: AnyObject {
    func activate(page: NotionPageReference)
    func activate(page: NotionPageReference, restoration: DurablePageRestoration?)
    func reselect(page: NotionPageReference)
    func panelDidShow()
    func panelDidHide()
}

extension NotionPageLoading {
    func activate(page: NotionPageReference, restoration: DurablePageRestoration?) {
        activate(page: page)
    }
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
    NotionEditorActivityHandling, NotionScrollHandling
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
    private let endEditing: @MainActor (WKWebView) -> Void
    private let scrollRestorer: NotionWebScrollRestorer
    private let editorActivityHandler: WeakNotionEditorActivityMessageHandler
    private let scrollHandler: WeakNotionScrollMessageHandler
    private var urlObservation: NSKeyValueObservation?
    private var evictionCancellable: AnyCancellable?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    @Published private var panelIsVisible = true
    private var stateBeforeSuspension: NotionWebSessionState = .unloaded
    private var loadedPageID: String?
    private var savedURL: URL?
    private var savedURLPageID: String?
    private var interactionStates: [String: Any] = [:]
    private var durableRestorations: [String: DurablePageRestoration] = [:]
    private var latestScrollSnapshots: [String: NotionScrollSnapshot] = [:]
    private var pendingScrollRestoration: DurablePageRestoration?
    private var isAttemptingDurableRestoration = false
    var onRestorationCaptured: (@MainActor (DurablePageRestoration) -> Void)?

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
        endEditing: @escaping @MainActor (WKWebView) -> Void = { webView in
            webView.window?.endEditing(for: webView)
            _ = webView.window?.makeFirstResponder(nil)
        },
        scrollRestorer: @escaping NotionWebScrollRestorer = {
            webView,
            restoration in
            NotionWebSession.restoreScroll(in: webView, restoration: restoration)
        }
    ) {
        let activityHandler = WeakNotionEditorActivityMessageHandler()
        let scrollHandler = WeakNotionScrollMessageHandler()
        self.webView = nil
        self.openURL = openURL
        self.loadRequest = loadRequest
        self.webViewFactory = webViewFactory
        self.scheduleEviction = scheduleEviction
        self.pauseMedia = pauseMedia
        self.stopLoading = stopLoading
        self.interactionStateReader = interactionStateReader
        self.interactionStateWriter = interactionStateWriter
        self.endEditing = endEditing
        self.scrollRestorer = scrollRestorer
        editorActivityHandler = activityHandler
        self.scrollHandler = scrollHandler
        super.init()
        if let webView {
            configure(webView)
        }
        installMemoryPressureSource()
    }

    private func configure(_ webView: WKWebView) {
        self.webView = webView
        Self.installBridges(
            in: webView.configuration.userContentController,
            activityHandler: editorActivityHandler,
            scrollHandler: scrollHandler
        )
        editorActivityHandler.delegate = self
        scrollHandler.delegate = self
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
        activate(page: page, restoration: nil)
    }

    func activate(
        page: NotionPageReference,
        restoration: DurablePageRestoration?
    ) {
        guard activePage?.pageID != page.pageID else {
            return
        }

        if let outgoingPage = activePage, let webView {
            captureAndTearDown(webView, page: outgoingPage)
        }
        activePage = page
        revealTopControls()
        if let restoration, restoration.pageID == page.pageID {
            durableRestorations[page.pageID] = restoration
        }
        savedURL = restoration?.lastURL ?? page.canonicalURL
        savedURLPageID = page.pageID
        guard panelIsVisible, state != .suspended else { return }
        restoreOrLoad(page: page)
    }

    func panelDidShow() {
        panelIsVisible = true
        if state == .suspended {
            resumeSuspendedWebView()
        } else if webView == nil, let activePage {
            restoreOrLoad(page: activePage)
        }
    }

    func panelDidHide() {
        panelIsVisible = false
        suspendWebViewIfNeeded()
    }

    private func load(
        _ url: URL,
        pageID: String? = nil,
        isDurableRestoration: Bool = false
    ) {
        savedURL = url
        savedURLPageID = pageID
        loadedPageID = pageID
        self.isAttemptingDurableRestoration = isDurableRestoration
        state = .loading
        loadRequest(ensureWebView(), URLRequest(url: url))
    }

    func reload() {
        guard let activePage else {
            return
        }

        revealTopControls()
        guard panelIsVisible else { return }
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

    func handleScrollSnapshot(_ snapshot: NotionScrollSnapshot) {
        guard let loadedPageID else { return }
        latestScrollSnapshots[loadedPageID] = snapshot
    }

    func evictInteractionSnapshots(retaining pageIDs: Set<String>) {
        let retained = Set(pageIDs.map { $0.lowercased() })
        interactionStates = interactionStates.filter {
            retained.contains($0.key.lowercased())
        }
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
        interactionStates.removeAll()
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
        if let activePage {
            captureAndTearDown(webView, page: activePage)
        } else {
            tearDown(webView)
        }
        state = .unloaded
    }

    private func suspendWebViewIfNeeded() {
        guard let webView, state != .suspended else {
            revealTopControls()
            return
        }

        stateBeforeSuspension = state
        revealTopControls()
        endEditing(webView)
        pauseMedia(webView)
        webView.removeFromSuperview()
        state = .suspended
        evictionCancellable?.cancel()
        evictionCancellable = scheduleEviction(Self.warmRetentionInterval) { [weak self] in
            self?.evictWarmWebView()
        }
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
        let webView = ensureWebView()
        if let interactionState = interactionStates[page.pageID] {
            isAttemptingDurableRestoration = false
            pendingScrollRestoration = nil
            interactionStateWriter(webView, interactionState)
            loadedPageID = page.pageID
            state = .loading
        } else {
            let durableRestoration = durableRestorations[page.pageID]
            pendingScrollRestoration = durableRestoration
            let restorationURL = durableRestoration?.lastURL
                ?? ((savedURLPageID == nil || savedURLPageID == page.pageID)
                    ? savedURL ?? page.canonicalURL
                    : page.canonicalURL)
            load(
                restorationURL,
                pageID: page.pageID,
                isDurableRestoration: durableRestoration != nil
                    && restorationURL != page.canonicalURL
            )
        }
    }

    private func captureAndTearDown(
        _ webView: WKWebView,
        page: NotionPageReference
    ) {
        endEditing(webView)
        if let state = interactionStateReader(webView) {
            interactionStates[page.pageID] = state
        }
        let trustedURL = webView.url ?? savedURL ?? page.canonicalURL
        let scroll = latestScrollSnapshots[page.pageID]
            ?? NotionScrollSnapshot(x: 0, y: 0, progress: 0)
        if let restoration = try? DurablePageRestoration(
            pageID: page.pageID,
            validatingLastURL: trustedURL,
            scrollX: scroll.x,
            scrollY: scroll.y,
            scrollProgress: scroll.progress,
            updatedAt: Date()
        ) {
            durableRestorations[page.pageID] = restoration
            onRestorationCaptured?(restoration)
        }
        tearDown(webView)
    }

    private func tearDown(_ webView: WKWebView) {
        stopLoading(webView)
        urlObservation?.invalidate()
        urlObservation = nil
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(
            forName: NotionEditorActivityBridge.handlerName,
            contentWorld: .page
        )
        controller.removeScriptMessageHandler(
            forName: NotionScrollBridge.handlerName,
            contentWorld: .page
        )
        controller.removeAllUserScripts()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        if self.webView === webView {
            self.webView = nil
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

    private static func installBridges(
        in userContentController: WKUserContentController,
        activityHandler: WeakNotionEditorActivityMessageHandler,
        scrollHandler: WeakNotionScrollMessageHandler
    ) {
        userContentController.addUserScript(
            WKUserScript(
                source: editorActivityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.add(
            activityHandler,
            contentWorld: .page,
            name: NotionEditorActivityBridge.handlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: scrollScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.add(
            scrollHandler,
            contentWorld: .page,
            name: NotionScrollBridge.handlerName
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

    private static let scrollScript = #"""
        (() => {
          if (window.__notionPiPScrollInstalled) return;
          window.__notionPiPScrollInstalled = true;
          let timer = null;

          const publish = () => {
            timer = null;
            const root = document.scrollingElement || document.documentElement;
            const maximum = Math.max(0, root.scrollHeight - window.innerHeight);
            const y = window.scrollY;
            window.webkit?.messageHandlers?.notionPiPScroll?.postMessage({
              x: window.scrollX,
              y,
              progress: maximum > 0 ? Math.min(1, Math.max(0, y / maximum)) : 0,
            });
          };

          window.addEventListener('scroll', () => {
            if (timer !== null) window.clearTimeout(timer);
            timer = window.setTimeout(publish, 120);
          }, { passive: true });
          window.addEventListener('pagehide', publish, { capture: true });
        })();
        """#

    private static func restoreScroll(
        in webView: WKWebView,
        restoration: DurablePageRestoration
    ) {
        Task { @MainActor [weak webView] in
            guard let webView else { return }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            while clock.now < deadline {
                let script = """
                    (() => {
                      const root = document.scrollingElement || document.documentElement;
                      if (!root) return false;
                      const maximum = Math.max(0, root.scrollHeight - window.innerHeight);
                      const target = maximum > 0
                        ? Math.max(\(restoration.scrollY), maximum * \(restoration.scrollProgress))
                        : \(restoration.scrollY);
                      window.scrollTo(\(restoration.scrollX), target);
                      return Math.abs(window.scrollY - target) < 4 || maximum === 0;
                    })()
                    """
                if let applied = try? await webView.evaluateJavaScript(script) as? Bool,
                   applied == true {
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
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
        publishNavigationState(.loading)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isAttemptingDurableRestoration = false
        publishNavigationState(.active)
        adoptResolvedPage(at: webView.url)
        if let restoration = pendingScrollRestoration,
           restoration.pageID == loadedPageID {
            pendingScrollRestoration = nil
            scrollRestorer(webView, restoration)
        }
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
        if fallBackFromFailedDurableRestoration() {
            return
        }
        revealTopControls()
        publishNavigationState(.failed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if fallBackFromFailedDurableRestoration() {
            return
        }
        revealTopControls()
        publishNavigationState(.failed(error.localizedDescription))
    }

    private func fallBackFromFailedDurableRestoration() -> Bool {
        guard isAttemptingDurableRestoration, let activePage else { return false }
        isAttemptingDurableRestoration = false
        pendingScrollRestoration = nil
        durableRestorations.removeValue(forKey: activePage.pageID)
        load(activePage.canonicalURL, pageID: activePage.pageID)
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
