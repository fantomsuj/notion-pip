import CoreFoundation
import Foundation

struct NotionEditorCaretGeometry: Equatable, Sendable {
    let left: Double
    let top: Double
    let bottom: Double
    let viewportWidth: Double
    let viewportHeight: Double
}

enum NotionEditorCaretUpdate: Equatable, Sendable {
    case visible(NotionEditorCaretGeometry)
    case hidden
}

enum NotionEditorCaretBridge {
    static let handlerName = "notionPiPEditorCaret"

    static func update(
        from body: Any,
        isMainFrame: Bool,
        scheme: String,
        host: String
    ) -> NotionEditorCaretUpdate? {
        guard isMainFrame,
              scheme.lowercased() == "https",
              ["app.notion.com", "notion.so", "www.notion.so"].contains(host.lowercased()),
              let values = body as? [String: Any],
              let visible = boolean(values["visible"])
        else {
            return nil
        }

        if !visible {
            return Set(values.keys) == ["visible"] ? .hidden : nil
        }

        guard Set(values.keys) == [
            "visible",
            "left",
            "top",
            "bottom",
            "viewportWidth",
            "viewportHeight",
        ],
            let left = number(values["left"]),
            let top = number(values["top"]),
            let bottom = number(values["bottom"]),
            let viewportWidth = number(values["viewportWidth"]),
            let viewportHeight = number(values["viewportHeight"]),
            left.isFinite,
            top.isFinite,
            bottom.isFinite,
            viewportWidth.isFinite,
            viewportHeight.isFinite,
            viewportWidth > 0,
            viewportHeight > 0,
            bottom >= top
        else {
            return nil
        }

        return .visible(
            NotionEditorCaretGeometry(
                left: left,
                top: top,
                bottom: bottom,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight
            )
        )
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.doubleValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.boolValue
    }

    static let script = #"""
        (() => {
          if (window.__notionPiPEditorCaretInstalled) return;
          window.__notionPiPEditorCaretInstalled = true;

          let frameRequest = null;
          const handler = window.webkit?.messageHandlers?.notionPiPEditorCaret;
          const hide = () => handler?.postMessage({ visible: false });
          const elementForNode = (node) =>
            node instanceof Element ? node : node?.parentElement;

          const publish = () => {
            frameRequest = null;
            try {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount !== 1 || !selection.isCollapsed ||
                  !selection.anchorNode || !selection.anchorNode.isConnected) {
                hide();
                return;
              }

              const editable = elementForNode(selection.anchorNode)
                ?.closest('[contenteditable]');
              const activeElement = document.activeElement;
              const selectedElement = selection.anchorNode.nodeType === Node.ELEMENT_NODE
                ? selection.anchorNode
                : selection.anchorNode.parentElement;
              if (!editable || !editable.isConnected || !editable.isContentEditable ||
                  editable.getAttribute('contenteditable') === 'false' ||
                  !(activeElement instanceof Element) ||
                  (activeElement !== editable && !editable.contains(activeElement)) ||
                  !selectedElement ||
                  (selectedElement !== editable && !editable.contains(selectedElement))) {
                hide();
                return;
              }

              const range = selection.getRangeAt(0);
              const rect = range.getClientRects()[0];
              if (!range.collapsed || !rect ||
                  !Number.isFinite(rect.left) || !Number.isFinite(rect.top) ||
                  !Number.isFinite(rect.bottom) || rect.height <= 0 ||
                  rect.bottom <= 0 || rect.top >= window.innerHeight ||
                  rect.right <= 0 || rect.left >= window.innerWidth ||
                  !Number.isFinite(window.innerWidth) ||
                  !Number.isFinite(window.innerHeight) ||
                  window.innerWidth <= 0 || window.innerHeight <= 0) {
                hide();
                return;
              }

              handler?.postMessage({
                visible: true,
                left: rect.left,
                top: rect.top,
                bottom: rect.bottom,
                viewportWidth: window.innerWidth,
                viewportHeight: window.innerHeight,
              });
            } catch (_) {
              hide();
            }
          };

          const schedule = () => {
            if (frameRequest !== null) return;
            frameRequest = window.requestAnimationFrame(publish);
          };

          for (const eventName of [
            'selectionchange',
            'input',
            'focusin',
            'focusout',
            'keyup',
            'pointerup',
          ]) {
            document.addEventListener(eventName, schedule, true);
          }
          document.addEventListener('scroll', schedule, { capture: true, passive: true });
          window.addEventListener('resize', schedule, { passive: true });
          window.visualViewport?.addEventListener('resize', schedule, { passive: true });
          schedule();
        })();
        """#
}
