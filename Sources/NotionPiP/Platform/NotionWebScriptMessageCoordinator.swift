import WebKit

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
              ["app.notion.com", "notion.com", "www.notion.com", "notion.so", "www.notion.so"]
                  .contains(host.lowercased()),
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
              ["app.notion.com", "notion.com", "www.notion.com", "notion.so", "www.notion.so"]
                  .contains(host.lowercased()),
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
protocol NotionWebScriptMessageHandling: AnyObject {
    func handleEditorActivity(
        _ activity: NotionEditorActivity,
        from webView: WKWebView?,
        generation: UInt
    )

    func handleScrollSnapshot(
        _ snapshot: NotionScrollSnapshot,
        from webView: WKWebView?,
        generation: UInt
    )

    func handleEditorCaretUpdate(
        _ update: NotionEditorCaretUpdate,
        from webView: WKWebView?,
        generation: UInt
    )
}

@MainActor
private final class WeakNotionEditorActivityMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionWebScriptMessageHandling)?
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
    weak var delegate: (any NotionWebScriptMessageHandling)?
    let generation: UInt

    init(generation: UInt) {
        self.generation = generation
    }

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
        delegate?.handleScrollSnapshot(
            snapshot,
            from: message.webView,
            generation: generation
        )
    }
}

@MainActor
private final class WeakNotionEditorCaretMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionWebScriptMessageHandling)?
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
final class NotionWebScriptMessageCoordinator {
    weak var delegate: (any NotionWebScriptMessageHandling)?
    private(set) var generation: UInt = 0

    private let removeBridges: NotionWebActivityBridgeRemover
    private var activityHandler: WeakNotionEditorActivityMessageHandler?
    private var scrollHandler: WeakNotionScrollMessageHandler?
    private var caretHandler: WeakNotionEditorCaretMessageHandler?

    init(
        removeBridges: @escaping NotionWebActivityBridgeRemover = { controller in
            controller.removeScriptMessageHandler(
                forName: NotionEditorActivityBridge.handlerName,
                contentWorld: .page
            )
            controller.removeScriptMessageHandler(
                forName: NotionScrollBridge.handlerName,
                contentWorld: .page
            )
            controller.removeScriptMessageHandler(
                forName: NotionEditorCaretBridge.handlerName,
                contentWorld: .page
            )
            controller.removeAllUserScripts()
        }
    ) {
        self.removeBridges = removeBridges
    }

    @discardableResult
    func install(in controller: WKUserContentController) -> UInt {
        generation &+= 1
        let activityHandler = WeakNotionEditorActivityMessageHandler(
            generation: generation
        )
        activityHandler.delegate = delegate
        let scrollHandler = WeakNotionScrollMessageHandler(generation: generation)
        scrollHandler.delegate = delegate
        let caretHandler = WeakNotionEditorCaretMessageHandler(generation: generation)
        caretHandler.delegate = delegate
        self.activityHandler = activityHandler
        self.scrollHandler = scrollHandler
        self.caretHandler = caretHandler

        controller.addUserScript(
            WKUserScript(
                source: Self.editorActivityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.add(
            activityHandler,
            contentWorld: .page,
            name: NotionEditorActivityBridge.handlerName
        )
        controller.addUserScript(
            WKUserScript(
                source: Self.scrollScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.add(
            scrollHandler,
            contentWorld: .page,
            name: NotionScrollBridge.handlerName
        )
        controller.addUserScript(
            WKUserScript(
                source: NotionEditorCaretBridge.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.add(
            caretHandler,
            contentWorld: .page,
            name: NotionEditorCaretBridge.handlerName
        )
        return generation
    }

    func remove(from controller: WKUserContentController) {
        activityHandler?.delegate = nil
        activityHandler = nil
        scrollHandler?.delegate = nil
        scrollHandler = nil
        caretHandler?.delegate = nil
        caretHandler = nil
        removeBridges(controller)
        generation &+= 1
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
}
