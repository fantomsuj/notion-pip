import AppKit
import WebKit

typealias NotionWebPopupRequestLoader = @MainActor (WKWebView, URLRequest) -> Void
typealias NotionWebPopupViewFactory = @MainActor (WKWebViewConfiguration) -> WKWebView
typealias NotionWebPopupWindowFactory = @MainActor () -> any NotionWebPopupWindowing

@MainActor
protocol NotionWebPopupCoordinating: AnyObject {
    func present(using configuration: WKWebViewConfiguration) -> WKWebView
    func close()
}

@MainActor
protocol NotionWebPopupWindowing: AnyObject {
    var onClose: (@MainActor () -> Void)? { get set }
    func present(webView: WKWebView)
    func close()
}

@MainActor
final class NotionWebPopupCoordinator: NSObject, NotionWebPopupCoordinating {
    private struct Popup {
        let window: any NotionWebPopupWindowing
        let webView: WKWebView
    }

    private let openURL: @MainActor (URL) -> Void
    private let loadRequest: NotionWebPopupRequestLoader
    private let makeWebView: NotionWebPopupViewFactory
    private let makeWindow: NotionWebPopupWindowFactory
    private var popup: Popup?

    init(
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        loadRequest: @escaping NotionWebPopupRequestLoader = { webView, request in
            webView.load(request)
        },
        makeWebView: @escaping NotionWebPopupViewFactory = { configuration in
            WKWebView(frame: .zero, configuration: configuration)
        },
        makeWindow: @escaping NotionWebPopupWindowFactory = {
            NotionLoginPopupWindow()
        }
    ) {
        self.openURL = openURL
        self.loadRequest = loadRequest
        self.makeWebView = makeWebView
        self.makeWindow = makeWindow
        super.init()
    }

    func present(using configuration: WKWebViewConfiguration) -> WKWebView {
        close()
        let webView = makeWebView(configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let window = makeWindow()
        window.onClose = { [weak self] in
            self?.detachCurrentPopup()
        }
        popup = Popup(window: window, webView: webView)
        window.present(webView: webView)
        return webView
    }

    func close() {
        guard let popup else { return }
        self.popup = nil
        popup.window.onClose = nil
        detach(popup.webView)
        popup.window.close()
    }

    func navigationPolicy(for url: URL?) -> WKNavigationActionPolicy {
        guard url?.scheme?.lowercased() == "https" else { return .cancel }
        switch WebNavigationDestination.classify(url) {
        case .trustedNotion, .externalWeb:
            return .allow
        case .unsupported:
            return .cancel
        }
    }

    func handleNewWindowRequest(
        _ request: URLRequest,
        in webView: WKWebView
    ) -> WKWebView? {
        guard popup?.webView === webView else { return nil }
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

    private func detachCurrentPopup() {
        guard let popup else { return }
        self.popup = nil
        popup.window.onClose = nil
        detach(popup.webView)
    }

    private func detach(_ webView: WKWebView) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}

extension NotionWebPopupCoordinator: WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard popup?.webView === webView else { return }
        close()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard popup?.webView === webView else { return .cancel }
        return navigationPolicy(for: navigationAction.request.url)
    }
}

extension NotionWebPopupCoordinator: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        handleNewWindowRequest(navigationAction.request, in: webView)
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard popup?.webView === webView else { return }
        close()
    }
}

@MainActor
private final class NotionLoginPopupWindow: NSWindow, NotionWebPopupWindowing {
    var onClose: (@MainActor () -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Sign in to Notion"
        isReleasedWhenClosed = false
    }

    func present(webView: WKWebView) {
        contentView = webView
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    override func close() {
        let closeHandler = onClose
        super.close()
        closeHandler?()
    }
}
