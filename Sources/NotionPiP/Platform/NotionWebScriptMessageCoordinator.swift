import Foundation
import WebKit

typealias NotionWebActivityBridgeRemover = @MainActor (WKUserContentController) -> Void

enum NotionEditorActivity: String, Equatable {
    case typingStarted
    case editingEnded
}

private enum NotionScriptMessageOrigin {
    private static let trustedHosts: Set<String> = [
        "app.notion.com",
        "notion.com",
        "www.notion.com",
        "notion.so",
        "www.notion.so",
    ]

    static func isTrusted(isMainFrame: Bool, scheme: String, host: String) -> Bool {
        isMainFrame
            && scheme.lowercased() == "https"
            && trustedHosts.contains(host.lowercased())
    }
}

enum NotionEditorActivityBridge {
    static let handlerName = "notionPiPChromeActivity"

    static func activity(
        from body: Any,
        isMainFrame: Bool,
        scheme: String,
        host: String
    ) -> NotionEditorActivity? {
        guard NotionScriptMessageOrigin.isTrusted(
            isMainFrame: isMainFrame,
            scheme: scheme,
            host: host
        ),
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
        guard NotionScriptMessageOrigin.isTrusted(
            isMainFrame: isMainFrame,
            scheme: scheme,
            host: host
        ),
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

enum NotionUsefulContentState: String, Equatable, Sendable {
    case ready
    case timedOut
}

struct NotionUsefulContentMessage: Equatable, Sendable {
    let state: NotionUsefulContentState
    let documentID: UUID
}

enum NotionUsefulContentBridge {
    static let handlerName = "notionPiPUsefulContent"
    static let documentIdentifierExpression =
        "window.__notionPiPUsefulContentDocumentID ?? null"

    static func message(
        from body: Any,
        isMainFrame: Bool,
        scheme: String,
        host: String
    ) -> NotionUsefulContentMessage? {
        guard NotionScriptMessageOrigin.isTrusted(
            isMainFrame: isMainFrame,
            scheme: scheme,
            host: host
        ), let values = body as? [String: Any],
           Set(values.keys) == ["state", "documentID"],
           let rawState = values["state"] as? String,
           let state = NotionUsefulContentState(rawValue: rawState),
           let rawDocumentID = values["documentID"] as? String,
           let documentID = UUID(uuidString: rawDocumentID)
        else {
            return nil
        }
        return NotionUsefulContentMessage(state: state, documentID: documentID)
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

    func handleUsefulContent(
        _ message: NotionUsefulContentMessage,
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
private final class WeakNotionUsefulContentMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (any NotionWebScriptMessageHandling)?
    let generation: UInt

    init(generation: UInt) {
        self.generation = generation
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let usefulContentMessage = NotionUsefulContentBridge.message(
            from: message.body,
            isMainFrame: message.frameInfo.isMainFrame,
            scheme: message.frameInfo.securityOrigin.protocol,
            host: message.frameInfo.securityOrigin.host
        ) else { return }
        delegate?.handleUsefulContent(
            usefulContentMessage,
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
    private var usefulContentHandler: WeakNotionUsefulContentMessageHandler?

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
                forName: NotionUsefulContentBridge.handlerName,
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
        let usefulContentHandler = WeakNotionUsefulContentMessageHandler(generation: generation)
        usefulContentHandler.delegate = delegate
        self.activityHandler = activityHandler
        self.scrollHandler = scrollHandler
        self.usefulContentHandler = usefulContentHandler

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
                source: Self.usefulContentScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.add(
            usefulContentHandler,
            contentWorld: .page,
            name: NotionUsefulContentBridge.handlerName
        )
        return generation
    }

    func remove(from controller: WKUserContentController) {
        activityHandler?.delegate = nil
        activityHandler = nil
        scrollHandler?.delegate = nil
        scrollHandler = nil
        usefulContentHandler?.delegate = nil
        usefulContentHandler = nil
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

    static func usefulContentScript(timeoutMilliseconds: Int = 30_000) -> String {
        #"""
        (() => {
          if (window.__notionPiPUsefulContentInstalled) return;
          window.__notionPiPUsefulContentInstalled = true;

          const documentID = window.crypto?.randomUUID?.();
          if (!documentID) return;
          Object.defineProperty(window, '__notionPiPUsefulContentDocumentID', {
            configurable: false,
            enumerable: false,
            value: documentID,
            writable: false,
          });

          let observer = null;
          let frameRequest = null;
          let timeout = null;
          let candidate = null;
          let stopped = false;

          const visibleContentRoot = () => {
            const roots = document.querySelectorAll(
              '.notion-page-content, [data-content-editable-root="true"]'
            );
            for (const root of roots) {
              const rect = root.getBoundingClientRect();
              const style = window.getComputedStyle(root);
              if (root.isConnected && rect.width > 0 && rect.height > 0 &&
                  style.display !== 'none' && style.visibility !== 'hidden') {
                return root;
              }
            }
            return null;
          };

          const stop = () => {
            if (stopped) return;
            stopped = true;
            observer?.disconnect();
            observer = null;
            if (frameRequest !== null) window.cancelAnimationFrame(frameRequest);
            frameRequest = null;
            if (timeout !== null) window.clearTimeout(timeout);
            timeout = null;
            window.removeEventListener('pagehide', stop, true);
          };

          const finish = (state) => {
            if (stopped) return;
            stop();
            window.webkit?.messageHandlers?.\#(NotionUsefulContentBridge.handlerName)?.postMessage({
              state,
              documentID,
            });
          };

          const inspect = () => {
            frameRequest = null;
            const root = visibleContentRoot();
            if (!root) {
              candidate = null;
              return;
            }
            if (root !== candidate) {
              candidate = root;
              frameRequest = window.requestAnimationFrame(inspect);
              return;
            }
            finish('\#(NotionUsefulContentState.ready.rawValue)');
          };

          const schedule = () => {
            if (!stopped && frameRequest === null) {
              frameRequest = window.requestAnimationFrame(inspect);
            }
          };

          const start = () => {
            frameRequest = null;
            if (!document.documentElement) {
              frameRequest = window.requestAnimationFrame(start);
              return;
            }
            observer = new MutationObserver(schedule);
            observer.observe(document.documentElement, {
              attributes: true,
              attributeFilter: ['class', 'hidden', 'style'],
              childList: true,
              subtree: true,
            });
            schedule();
          };
          window.addEventListener('pagehide', stop, { capture: true, once: true });
          timeout = window.setTimeout(
            () => finish('\#(NotionUsefulContentState.timedOut.rawValue)'),
            \#(timeoutMilliseconds)
          );
          start();
        })();
        """#
    }
}
