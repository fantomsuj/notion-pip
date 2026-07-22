import Combine
import AppKit
import WebKit

typealias NotionWebRequestLoader = @MainActor (WKWebView, URLRequest) -> Void

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
}

@MainActor
enum NotionWebSessionState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

@MainActor
final class NotionWebSession: NSObject, NotionPageLoading, ObservableObject,
    NotionEditorActivityHandling
{
    static let newPageURL = URL(string: "https://www.notion.so/new")!

    let webView: WKWebView
    @Published private(set) var state: NotionWebSessionState = .idle
    @Published private(set) var isCreatingNewPage = false
    @Published private(set) var isTypingInPage = false
    private(set) var activePage: NotionPageReference?
    var onPageResolved: (@MainActor (NotionPageReference) -> Void)?
    private let openURL: @MainActor (URL) -> Void
    private let loadRequest: NotionWebRequestLoader
    private let editorActivityHandler: WeakNotionEditorActivityMessageHandler
    private var urlObservation: NSKeyValueObservation?

    init(
        webView: WKWebView? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        loadRequest: @escaping NotionWebRequestLoader = { webView, request in
            webView.load(request)
        }
    ) {
        let activityHandler = WeakNotionEditorActivityMessageHandler()
        self.webView = webView ?? Self.makeWebView()
        self.openURL = openURL
        self.loadRequest = loadRequest
        editorActivityHandler = activityHandler
        super.init()
        Self.installEditorActivityBridge(
            in: self.webView.configuration.userContentController,
            handler: activityHandler
        )
        activityHandler.delegate = self
        self.webView.navigationDelegate = self
        urlObservation = self.webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.adoptResolvedPage(at: webView.url)
            }
        }
    }

    func activate(page: NotionPageReference) {
        guard activePage?.pageID != page.pageID else {
            return
        }

        activePage = page
        revealTopControls()
        state = .loading
        loadRequest(webView, URLRequest(url: page.canonicalURL))
    }

    func createNewPage() {
        guard !isCreatingNewPage else {
            return
        }

        isCreatingNewPage = true
        revealTopControls()
        state = .loading
        loadRequest(webView, URLRequest(url: Self.newPageURL))
    }

    func reload() {
        guard activePage != nil else {
            return
        }

        revealTopControls()
        state = .loading
        webView.reload()
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

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
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
        state = .loading
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .ready
        isCreatingNewPage = false
        adoptResolvedPage(at: webView.url)
    }

    func adoptResolvedPage(at url: URL?) {
        guard let url,
              let resolvedPage = try? NotionPageReference(validating: url),
              resolvedPage.pageID != activePage?.pageID
        else {
            return
        }

        revealTopControls()
        activePage = resolvedPage
        onPageResolved?(resolvedPage)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isCreatingNewPage = false
        revealTopControls()
        state = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isCreatingNewPage = false
        revealTopControls()
        state = .failed(error.localizedDescription)
    }
}
