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
typealias NotionWebAttachmentScheduler = @MainActor (
    @escaping @MainActor () -> Void
) -> Void
typealias NotionWebURLObservationInvalidator = @MainActor (NSKeyValueObservation) -> Void
typealias NotionWebActivityBridgeRemover = @MainActor (WKUserContentController) -> Void

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
    func handleEditorActivity(
        _ activity: NotionEditorActivity,
        from webView: WKWebView?,
        generation: UInt
    )
}

@MainActor
private protocol NotionScrollHandling: AnyObject {
    func handleScrollSnapshot(_ snapshot: NotionScrollSnapshot)
}

@MainActor
private protocol NotionEditorCaretHandling: AnyObject {
    func handleEditorCaretUpdate(
        _ update: NotionEditorCaretUpdate,
        from webView: WKWebView?,
        generation: UInt
    )
}

@MainActor
private final class WeakNotionEditorActivityMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionEditorActivityHandling)?
    let generation: UInt

    init(generation: UInt) {
        self.generation = generation
    }

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

        delegate?.handleEditorActivity(
            activity,
            from: message.webView,
            generation: generation
        )
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
private final class WeakNotionEditorCaretMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionEditorCaretHandling)?
    let generation: UInt

    init(generation: UInt) {
        self.generation = generation
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let update = NotionEditorCaretBridge.update(
            from: message.body,
            isMainFrame: message.frameInfo.isMainFrame,
            scheme: message.frameInfo.securityOrigin.protocol,
            host: message.frameInfo.securityOrigin.host
        ) else {
            return
        }
        delegate?.handleEditorCaretUpdate(
            update,
            from: message.webView,
            generation: generation
        )
    }
}

@MainActor
protocol NotionPageLoading: AnyObject {
    func activate(page: NotionPageReference)
    func activate(page: NotionPageReference, restoration: DurablePageRestoration?)
    func reloadPinnedPage(_ page: NotionPageReference)
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
    case offline
    case failed(String)
}

@MainActor
final class NotionWebSession: NSObject, NotionPageLoading, ObservableObject,
    NotionEditorActivityHandling, NotionScrollHandling, NotionEditorCaretHandling
{
    static let warmRetentionInterval = NotionWebLifecycleController.defaultWarmRetentionInterval

    @Published private(set) var webView: WKWebView?
    var state: NotionWebSessionState { lifecycleController.state }
    @Published private(set) var isTypingInPage = false
    @Published private(set) var editorCaretGeometry: NotionEditorCaretGeometry?
    private(set) var activePage: NotionPageReference?
    var onPageResolved: (@MainActor (NotionPageReference) -> Void)?
    private let openURL: @MainActor (URL) -> Void
    private let loadRequest: NotionWebRequestLoader
    private let webViewFactory: NotionWebViewFactory
    private let lifecycleController: NotionWebLifecycleController
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
    private let removeActivityBridge: NotionWebActivityBridgeRemover
    private var editorActivityHandler: WeakNotionEditorActivityMessageHandler?
    private var scrollHandler: WeakNotionScrollMessageHandler?
    private var editorCaretHandler: WeakNotionEditorCaretMessageHandler?
    private var urlObservation: NSKeyValueObservation?
    private var webViewGeneration: UInt = 0
    private var lifecycleObservation: AnyCancellable?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var panelIsVisible: Bool { lifecycleController.isVisible }
    private var loadedPageID: String?
    private var savedURL: URL?
    private var savedURLPageID: String?
    private var interactionStates: [String: Any] = [:]
    private var durableRestorations: [String: DurablePageRestoration] = [:]
    private var latestScrollSnapshots: [String: NotionScrollSnapshot] = [:]
    private var pendingScrollRestoration: DurablePageRestoration?
    private var isAttemptingDurableRestoration = false
    var onRestorationCaptured: (@MainActor (DurablePageRestoration) -> Void)?
    private var selectionCaptureGeneration = 0
    private var savedEditorSelection: (
        pageID: String,
        snapshot: NotionEditorSelectionSnapshot
    )?

    func rememberCurrentEditorCursor(completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard let webView, let pageID = activePage?.pageID,
              loadedPageID == pageID, Self.isTrustedSelectionContext(webView, pageID: pageID)
        else { completion(false); return }
        selectionEvaluator(webView, .capture) { [weak self] result in
            guard let self, case let .success(value) = result,
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
            let inserted = (try? result.get() as? Bool) == true
            if inserted { self?.savedEditorSelection = nil }
            completion(inserted)
        }
    }

    var shouldHostWebView: Bool {
        lifecycleController.shouldHostWebView(hasWebView: webView != nil)
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
                forName: NotionEditorCaretBridge.handlerName,
                contentWorld: .page
            )
            $0.removeAllUserScripts()
        }
    ) {
        self.webView = nil
        self.openURL = openURL
        self.loadRequest = loadRequest
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
        self.removeActivityBridge = removeActivityBridge
        super.init()
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
        webViewGeneration &+= 1
        let generation = webViewGeneration
        let activityHandler = WeakNotionEditorActivityMessageHandler(generation: generation)
        activityHandler.delegate = self
        let scrollHandler = WeakNotionScrollMessageHandler()
        scrollHandler.delegate = self
        let caretHandler = WeakNotionEditorCaretMessageHandler(generation: generation)
        caretHandler.delegate = self
        editorActivityHandler = activityHandler
        self.scrollHandler = scrollHandler
        editorCaretHandler = caretHandler
        self.webView = webView
        Self.installBridges(
            in: webView.configuration.userContentController,
            activityHandler: activityHandler,
            scrollHandler: scrollHandler,
            caretHandler: caretHandler
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.adoptResolvedPage(
                    at: webView.url,
                    from: webView,
                    generation: generation
                )
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
        guard activePage?.canonicalURL != page.canonicalURL else {
            return
        }

        if let outgoingPage = activePage, let webView {
            invalidateEditorSelection()
            if outgoingPage.pageID == page.pageID {
                interactionStates.removeValue(forKey: page.pageID)
                durableRestorations.removeValue(forKey: page.pageID)
                latestScrollSnapshots.removeValue(forKey: page.pageID)
                _ = retire(webView)
            } else {
                captureAndTearDown(webView, page: outgoingPage)
            }
        }
        activePage = page
        revealTopControls()
        if let restoration, restoration.pageID == page.pageID {
            durableRestorations[page.pageID] = restoration
        }
        savedURL = restoration?.lastURL ?? page.canonicalURL
        savedURLPageID = page.pageID
        guard panelIsVisible, state != .suspended else {
            if !panelIsVisible, webView != nil {
                suspendWebViewIfNeeded()
            }
            return
        }
        restoreOrLoad(page: page)
    }

    func reloadPinnedPage(_ page: NotionPageReference) {
        invalidateEditorSelection()
        activePage = page
        revealTopControls()
        interactionStates.removeValue(forKey: page.pageID)
        durableRestorations.removeValue(forKey: page.pageID)
        latestScrollSnapshots.removeValue(forKey: page.pageID)
        pendingScrollRestoration = nil
        isAttemptingDurableRestoration = false
        savedURL = page.canonicalURL
        savedURLPageID = page.pageID
        load(page.canonicalURL, pageID: page.pageID)
    }

    func panelDidShow() {
        let wasHidden = !panelIsVisible
        let retainedWebView = webView
        let retainedPageID = loadedPageID
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
    }

    func panelDidHide() {
        lifecycleController.panelDidHide()
        captureSelectionAndSuspendIfNeeded()
    }

    private func load(
        _ url: URL,
        pageID: String? = nil,
        isDurableRestoration: Bool = false
    ) {
        invalidateEditorSelection()
        savedURL = url
        savedURLPageID = pageID
        loadedPageID = pageID
        self.isAttemptingDurableRestoration = isDurableRestoration
        lifecycleController.setState(.loading)
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
            lifecycleController.setState(.loading)
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
        lifecycleController.setEvictionProtected(isTyping)
    }

    func handleScrollSnapshot(_ snapshot: NotionScrollSnapshot) {
        guard let loadedPageID else { return }
        latestScrollSnapshots[loadedPageID] = snapshot
    }

    func handleEditorCaretUpdate(
        _ update: NotionEditorCaretUpdate,
        from webView: WKWebView?
    ) {
        handleEditorCaretUpdate(update, from: webView, generation: webViewGeneration)
    }

    func handleEditorCaretUpdate(
        _ update: NotionEditorCaretUpdate,
        from webView: WKWebView?,
        generation: UInt
    ) {
        guard let webView, isCurrent(webView, generation: generation) else {
            return
        }
        switch update {
        case let .visible(geometry):
            if editorCaretGeometry != geometry {
                editorCaretGeometry = geometry
            }
        case .hidden:
            clearEditorCaretGeometry()
        }
    }

    func evictInteractionSnapshots(retaining pageIDs: Set<String>) {
        let retained = Set(pageIDs.map { $0.lowercased() })
        interactionStates = interactionStates.filter {
            retained.contains($0.key.lowercased())
        }
    }

    func handleEditorActivity(
        _ activity: NotionEditorActivity,
        from webView: WKWebView?
    ) {
        handleEditorActivity(activity, from: webView, generation: webViewGeneration)
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
            interactionStates.removeAll()
        }
    }

    func evictWarmWebView() {
        _ = lifecycleController.requestEvictionIfEligible()
    }

    private func evictWarmWebView(afterLifecycleDecision: Bool) {
        guard afterLifecycleDecision, let webView else { return }

        if let activePage {
            captureAndTearDown(webView, page: activePage)
        } else {
            _ = retire(webView)
        }
        lifecycleController.didEvictWebView()
    }

    @discardableResult
    private func retire(_ webView: WKWebView) -> Bool {
        guard isCurrent(webView) else {
            return false
        }

        lifecycleController.cancelWarmRetention()
        editorActivityHandler?.delegate = nil
        editorActivityHandler = nil
        scrollHandler?.delegate = nil
        scrollHandler = nil
        editorCaretHandler?.delegate = nil
        editorCaretHandler = nil
        webViewGeneration &+= 1
        self.webView = nil
        loadedPageID = nil
        if let urlObservation {
            invalidateURLObservation(urlObservation)
            self.urlObservation = nil
        }
        removeActivityBridge(webView.configuration.userContentController)
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
        return generation == nil || generation == webViewGeneration
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
        clearEditorCaretGeometry()
    }

    private func clearEditorCaretGeometry() {
        if editorCaretGeometry != nil {
            editorCaretGeometry = nil
        }
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
        let webView = ensureWebView()
        if let interactionState = interactionStates[page.pageID] {
            isAttemptingDurableRestoration = false
            pendingScrollRestoration = nil
            interactionStateWriter(webView, interactionState)
            interactionStates.removeValue(forKey: page.pageID)
            loadedPageID = page.pageID
            lifecycleController.setState(.loading)
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
        guard isCurrent(webView) else { return }
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

    private static func installBridges(
        in userContentController: WKUserContentController,
        activityHandler: WeakNotionEditorActivityMessageHandler,
        scrollHandler: WeakNotionScrollMessageHandler,
        caretHandler: WeakNotionEditorCaretMessageHandler
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
        userContentController.addUserScript(
            WKUserScript(
                source: NotionEditorCaretBridge.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.add(
            caretHandler,
            contentWorld: .page,
            name: NotionEditorCaretBridge.handlerName
        )
    }

    private static let editorActivityScript = #"""
        (() => {
          if (window.__notionPiPChromeActivityInstalled) return;
          window.__notionPiPChromeActivityInstalled = true;

          var isTyping = false;

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
        guard isCurrent(webView) else {
            return .cancel
        }
        return navigationPolicy(
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
        guard isCurrent(webView) else { return }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(.loading)
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isCurrent(webView) else { return }
        isAttemptingDurableRestoration = false
        invalidateEditorSelection()
        publishNavigationState(.active)
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
        adoptResolvedPage(
            at: webView.url,
            from: webView,
            generation: webViewGeneration
        )
        if let restoration = pendingScrollRestoration,
           restoration.pageID == loadedPageID {
            pendingScrollRestoration = nil
            scrollRestorer(webView, restoration)
        }
    }

    func adoptResolvedPage(at url: URL?) {
        guard let webView else { return }
        adoptResolvedPage(at: url, from: webView, generation: webViewGeneration)
    }

    func adoptResolvedPage(at url: URL?, from webView: WKWebView) {
        adoptResolvedPage(at: url, from: webView, generation: webViewGeneration)
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
        savedURL = url
        savedURLPageID = resolvedPage.pageID
        onPageResolved?(resolvedPage)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard isCurrent(webView) else { return }
        guard !isCancellation(error) else {
            invalidateEditorSelectionAndSuspendIfHidden()
            return
        }
        if fallBackFromFailedDurableRestoration() {
            return
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(navigationFailureState(for: error))
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isCurrent(webView) else { return }
        guard !isCancellation(error) else {
            invalidateEditorSelectionAndSuspendIfHidden()
            return
        }
        if fallBackFromFailedDurableRestoration() {
            return
        }
        revealTopControls()
        invalidateEditorSelection()
        publishNavigationState(navigationFailureState(for: error))
        if !panelIsVisible {
            suspendWebViewIfNeeded()
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    private func navigationFailureState(for error: Error) -> NotionWebSessionState {
        Self.isOfflineNavigationError(error)
            ? .offline
            : .failed("Notion couldn't load this page.")
    }

    static func isOfflineNavigationError(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
        ].contains(error.code)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isCurrent(webView) else { return }

        revealTopControls()
        invalidateEditorSelection()
        let page = activePage
        if let page {
            savedURL = page.canonicalURL
            savedURLPageID = page.pageID
        }

        // WebKit cannot provide unsaved DOM edits after its renderer exits, so only
        // the canonical page can be recovered. Never restore stale interaction state.
        if let page {
            interactionStates.removeValue(forKey: page.pageID)
            durableRestorations.removeValue(forKey: page.pageID)
            latestScrollSnapshots.removeValue(forKey: page.pageID)
        }
        pendingScrollRestoration = nil
        isAttemptingDurableRestoration = false
        guard retire(webView) else { return }

        guard panelIsVisible, let page else {
            lifecycleController.setState(.unloaded)
            return
        }
        load(page.canonicalURL, pageID: page.pageID)
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
        guard isCurrent(webView) else { return nil }
        return handleNewWindowRequest(navigationAction.request, in: webView)
    }

    func handleNewWindowRequest(
        _ request: URLRequest,
        in webView: WKWebView
    ) -> WKWebView? {
        guard isCurrent(webView) else { return nil }
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
