import Combine
import AppKit
import WebKit

typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void
typealias NotionWebViewFactory = @MainActor () -> WKWebView
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
              ["notion.so", "www.notion.so"].contains(host.lowercased()),
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

enum NotionPageSurface: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case live = "Notion"

    var id: String { rawValue }
}

@MainActor
final class NotionWebSession: NSObject, NotionPageLoading, ObservableObject,
    NotionEditorActivityHandling
{
    static let newPageURL = URL(string: "https://www.notion.so/new")!
    static let warmRetentionInterval: TimeInterval = 60

    @Published private(set) var webView: WKWebView?
    @Published private(set) var state: NotionWebSessionState = .unloaded
    @Published private(set) var surface: NotionPageSurface = .preview
    @Published private(set) var isCreatingNewPage = false
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
    private let editorActivityHandler: WeakNotionEditorActivityMessageHandler
    private var urlObservation: NSKeyValueObservation?
    private var evictionCancellable: AnyCancellable?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    @Published private var panelIsVisible = true
    private var hasPendingNewPageNavigation = false
    private var stateBeforeSuspension: NotionWebSessionState = .unloaded
    private var loadedPageID: String?
    private var savedURL: URL?
    private var savedURLPageID: String?
    private var savedInteractionState: Any?
    private var savedInteractionPageID: String?

    var shouldHostWebView: Bool {
        surface == .live
            && panelIsVisible
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
        guard activePage?.pageID != page.pageID else {
            return
        }

        let selectedPageChanged = activePage != nil
        isCreatingNewPage = false
        hasPendingNewPageNavigation = false
        activePage = page
        revealTopControls()
        savedURL = page.canonicalURL
        savedURLPageID = page.pageID
        if selectedPageChanged {
            savedInteractionState = nil
            savedInteractionPageID = nil
        }
        guard surface == .live, panelIsVisible, state != .suspended else { return }
        load(page.canonicalURL, pageID: page.pageID)
    }

    func reselect(page: NotionPageReference) {
        guard activePage?.pageID == page.pageID, isCreatingNewPage else {
            return
        }

        isCreatingNewPage = false
        hasPendingNewPageNavigation = false
        revealTopControls()
        savedURL = page.canonicalURL
        savedURLPageID = page.pageID
        savedInteractionState = nil
        savedInteractionPageID = nil
        guard surface == .live, panelIsVisible, state != .suspended else { return }
        load(page.canonicalURL, pageID: page.pageID)
    }

    func showLiveSurface() {
        surface = .live
        guard panelIsVisible else { return }
        if state == .suspended {
            resumeSuspendedWebView()
            return
        }
        guard let activePage else { return }
        if webView == nil {
            restoreOrLoad(page: activePage)
        } else if loadedPageID != activePage.pageID {
            load(activePage.canonicalURL, pageID: activePage.pageID)
        }
    }

    func showPreviewSurface() {
        surface = .preview
        suspendWebViewIfNeeded()
    }

    func panelDidShow() {
        panelIsVisible = true
        guard surface == .live else { return }
        if hasPendingNewPageNavigation {
            hasPendingNewPageNavigation = false
            evictionCancellable?.cancel()
            evictionCancellable = nil
            load(Self.newPageURL)
            return
        }
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

    private func load(_ url: URL, pageID: String? = nil) {
        savedURL = url
        savedURLPageID = pageID
        loadedPageID = pageID
        state = .loading
        loadRequest(ensureWebView(), URLRequest(url: url))
    }

    func createNewPage() {
        guard !isCreatingNewPage else {
            return
        }

        isCreatingNewPage = true
        surface = .live
        revealTopControls()
        guard panelIsVisible else {
            hasPendingNewPageNavigation = true
            return
        }
        load(Self.newPageURL)
    }

    func reload() {
        guard let activePage else {
            return
        }

        revealTopControls()
        guard surface == .live, panelIsVisible else { return }
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
              !(surface == .live && panelIsVisible)
        else {
            return
        }
        evictWarmWebView()
    }

    func evictWarmWebView() {
        guard state == .suspended,
              !isTypingInPage,
              !(surface == .live && panelIsVisible),
              let webView
        else {
            return
        }

        evictionCancellable?.cancel()
        evictionCancellable = nil
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
        webView.removeFromSuperview()
        self.webView = nil
        state = .unloaded
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
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        revealTopControls()
        publishNavigationState(.loading)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publishNavigationState(.active)
        adoptResolvedPage(at: webView.url)
        isCreatingNewPage = false
    }

    func adoptResolvedPage(at url: URL?) {
        let hasAdoptionAuthority: Bool
        if let loadedPageID {
            hasAdoptionAuthority = loadedPageID == activePage?.pageID
        } else {
            hasAdoptionAuthority = isCreatingNewPage
        }

        guard let url,
              let resolvedPage = try? NotionPageReference(validating: url),
              webView?.url == url,
              hasAdoptionAuthority,
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
        isCreatingNewPage = false
        revealTopControls()
        publishNavigationState(.failed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isCreatingNewPage = false
        revealTopControls()
        publishNavigationState(.failed(error.localizedDescription))
    }
}
