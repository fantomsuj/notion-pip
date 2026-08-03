import Foundation
import WebKit

typealias NotionEditorSelectionEvaluationCompletion = @MainActor (
    Result<Any?, Error>
) -> Void
typealias NotionEditorSelectionEvaluator = @MainActor (
    WKWebView,
    NotionEditorSelectionEvaluation,
    @escaping NotionEditorSelectionEvaluationCompletion
) -> Void

struct NotionEditorSelectionSnapshot: Equatable {
    static let version = 1
    private static let maximumPathDepth = 128
    private static let maximumOffset = 10_000_000

    let token: String
    let editablePath: [Int]
    let anchorPath: [Int]
    let anchorOffset: Int
    let focusPath: [Int]
    let focusOffset: Int

    init?(javaScriptValue: Any?) {
        guard let value = javaScriptValue as? [String: Any],
              value["version"] as? Int == Self.version,
              let token = value["token"] as? String,
              !token.isEmpty,
              token.utf8.count <= 128,
              let editablePath = Self.path(value["editablePath"]),
              let anchorPath = Self.path(value["anchorPath"]),
              let anchorOffset = Self.offset(value["anchorOffset"]),
              let focusPath = Self.path(value["focusPath"]),
              let focusOffset = Self.offset(value["focusOffset"])
        else {
            return nil
        }

        self.token = token
        self.editablePath = editablePath
        self.anchorPath = anchorPath
        self.anchorOffset = anchorOffset
        self.focusPath = focusPath
        self.focusOffset = focusOffset
    }

    var javaScriptValue: [String: Any] {
        [
            "version": Self.version,
            "token": token,
            "editablePath": editablePath,
            "anchorPath": anchorPath,
            "anchorOffset": anchorOffset,
            "focusPath": focusPath,
            "focusOffset": focusOffset,
        ]
    }

    private static func path(_ value: Any?) -> [Int]? {
        guard let components = value as? [Any],
              components.count <= maximumPathDepth
        else {
            return nil
        }

        var path: [Int] = []
        path.reserveCapacity(components.count)
        for component in components {
            guard let index = component as? Int,
                  (0 ... maximumOffset).contains(index)
            else {
                return nil
            }
            path.append(index)
        }
        return path
    }

    private static func offset(_ value: Any?) -> Int? {
        guard let offset = value as? Int,
              (0 ... maximumOffset).contains(offset)
        else {
            return nil
        }
        return offset
    }
}

enum NotionEditorSelectionEvaluation: Equatable {
    case capture
    case restore(NotionEditorSelectionSnapshot)
    case insert(String, at: NotionEditorSelectionSnapshot)

    var script: String {
        switch self {
        case .capture:
            Self.captureScript
        case let .restore(snapshot):
            Self.restoreScript(for: snapshot)
        case let .insert(text, snapshot):
            Self.insertScript(text: text, snapshot: snapshot)
        }
    }

    private static let captureScript = #"""
        (() => {
          const selection = window.getSelection();
          const activeElement = document.activeElement;
          if (!selection || selection.rangeCount === 0 ||
              !selection.anchorNode || !selection.focusNode ||
              !(activeElement instanceof Element)) {
            return null;
          }

          const editable = activeElement.closest('[contenteditable]');
          if (!editable || !editable.isConnected || !editable.isContentEditable ||
              editable.getAttribute('contenteditable') === 'false') {
            return null;
          }

          const containsNode = (root, node) =>
            node === root || root.contains(
              node.nodeType === Node.ELEMENT_NODE ? node : node.parentNode
            );
          if (!containsNode(editable, selection.anchorNode) ||
              !containsNode(editable, selection.focusNode)) {
            return null;
          }

          const pathFrom = (root, node) => {
            const path = [];
            let current = node;
            while (current && current !== root) {
              const parent = current.parentNode;
              if (!parent) return null;
              const index = Array.prototype.indexOf.call(parent.childNodes, current);
              if (index < 0) return null;
              path.push(index);
              current = parent;
            }
            return current === root ? path.reverse() : null;
          };

          const editablePath = pathFrom(document.documentElement, editable);
          const anchorPath = pathFrom(editable, selection.anchorNode);
          const focusPath = pathFrom(editable, selection.focusNode);
          if (!editablePath || !anchorPath || !focusPath) return null;

          const token = globalThis.crypto?.randomUUID?.() ??
            `notion-pip-${Date.now()}-${Math.random()}`;
          Object.defineProperty(editable, '__notionPiPSelectionToken', {
            configurable: true,
            value: token,
          });

          return {
            version: 1,
            token,
            editablePath,
            anchorPath,
            anchorOffset: selection.anchorOffset,
            focusPath,
            focusOffset: selection.focusOffset,
          };
        })();
        """#

    private static func restoreScript(for snapshot: NotionEditorSelectionSnapshot) -> String {
        guard JSONSerialization.isValidJSONObject(snapshot.javaScriptValue),
              let data = try? JSONSerialization.data(withJSONObject: snapshot.javaScriptValue),
              let value = String(data: data, encoding: .utf8)
        else {
            return "false"
        }

        return #"""
            (() => {
              const snapshot = \#(value);
              const resolve = (root, path) => {
                let node = root;
                for (const index of path) {
                  if (!Number.isSafeInteger(index) || index < 0 ||
                      !node?.childNodes || index >= node.childNodes.length) {
                    return null;
                  }
                  node = node.childNodes[index];
                }
                return node;
              };
              const validOffset = (node, offset) => {
                if (!node || !Number.isSafeInteger(offset) || offset < 0) return false;
                if (node.nodeType === Node.TEXT_NODE ||
                    node.nodeType === Node.CDATA_SECTION_NODE) {
                  return offset <= (node.nodeValue?.length ?? 0);
                }
                return offset <= node.childNodes.length;
              };

              const editable = resolve(document.documentElement, snapshot.editablePath);
              if (!(editable instanceof Element) || !editable.isConnected ||
                  !editable.isContentEditable ||
                  editable.__notionPiPSelectionToken !== snapshot.token) {
                return false;
              }

              const anchor = resolve(editable, snapshot.anchorPath);
              const focus = resolve(editable, snapshot.focusPath);
              if (!validOffset(anchor, snapshot.anchorOffset) ||
                  !validOffset(focus, snapshot.focusOffset)) {
                delete editable.__notionPiPSelectionToken;
                return false;
              }

              editable.focus({ preventScroll: true });
              const selection = window.getSelection();
              if (!selection || typeof selection.setBaseAndExtent !== 'function') {
                delete editable.__notionPiPSelectionToken;
                return false;
              }
              selection.setBaseAndExtent(
                anchor,
                snapshot.anchorOffset,
                focus,
                snapshot.focusOffset
              );
              delete editable.__notionPiPSelectionToken;
              return true;
            })();
            """#
    }

    private static func insertScript(
        text: String,
        snapshot: NotionEditorSelectionSnapshot
    ) -> String {
        let payload: [String: Any] = ["snapshot": snapshot.javaScriptValue, "text": text]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let value = String(data: data, encoding: .utf8)
        else { return "false" }

        return #"""
            (() => {
              const payload = \#(value);
              const snapshot = payload.snapshot;
              const resolve = (root, path) => {
                let node = root;
                for (const index of path) {
                  if (!node?.childNodes || index < 0 || index >= node.childNodes.length) return null;
                  node = node.childNodes[index];
                }
                return node;
              };
              const editable = resolve(document.documentElement, snapshot.editablePath);
              if (!(editable instanceof Element) || !editable.isConnected ||
                  !editable.isContentEditable ||
                  editable.__notionPiPSelectionToken !== snapshot.token) return false;
              const anchor = resolve(editable, snapshot.anchorPath);
              const focus = resolve(editable, snapshot.focusPath);
              if (!anchor || !focus) return false;
              try {
                editable.focus({ preventScroll: true });
                const selection = window.getSelection();
                selection.setBaseAndExtent(anchor, snapshot.anchorOffset, focus, snapshot.focusOffset);
                const range = selection.getRangeAt(0);
                range.deleteContents();
                const inserted = document.createTextNode(payload.text);
                range.insertNode(inserted);
                range.setStartAfter(inserted);
                range.collapse(true);
                selection.removeAllRanges();
                selection.addRange(range);
                editable.dispatchEvent(new InputEvent('input', {
                  bubbles: true, inputType: 'insertText', data: payload.text,
                }));
                delete editable.__notionPiPSelectionToken;
                return true;
              } catch (_) {
                delete editable.__notionPiPSelectionToken;
                return false;
              }
            })();
            """#
    }
}
