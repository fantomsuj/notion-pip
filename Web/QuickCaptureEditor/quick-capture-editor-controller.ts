import { Editor } from "@tiptap/core";
import type { JSONContent } from "@tiptap/core";
import Placeholder from "@tiptap/extension-placeholder";
import TaskItem from "@tiptap/extension-task-item";
import TaskList from "@tiptap/extension-task-list";
import StarterKit from "@tiptap/starter-kit";

import { BridgeClient } from "./bridge/bridge-client.ts";
import {
  DebouncedChangePublisher,
  requireAutosaveAcknowledgement,
} from "./bridge/debounced-change-publisher.ts";
import { isCompositionKey } from "./block-commands.ts";
import { FormattingToolbarController } from "./controllers/formatting-toolbar-controller.ts";
import { SlashMenuController } from "./controllers/slash-menu-controller.ts";
import {
  canInstallSnapshot,
  normalizeDocument,
  routeTitleKey,
} from "./editor-state.ts";
import { isLinkPaste } from "./formatting.ts";
import {
  isBridgeReply,
  makeRequest,
  type BridgeReply,
  type BridgeRequest,
  type ConflictAction,
  type EditorSnapshot,
} from "./protocol.ts";
import {
  EditorTransitionGate,
  conflictTransitionOperation,
} from "./state/editor-transition-gate.ts";

export interface NativeCaptureBridge {
  postMessage(request: BridgeRequest): Promise<unknown>;
}

export interface QuickCaptureEditorElements {
  readonly editor: HTMLElement;
  readonly title: HTMLInputElement;
  readonly status: HTMLElement;
  readonly slashMenu: HTMLElement;
  readonly formatToolbar: HTMLElement;
  readonly page: HTMLElement | null;
  readonly newNoteButton: HTMLButtonElement | null;
  readonly retryButton: HTMLButtonElement | null;
}

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        captureBridge?: NativeCaptureBridge;
      };
    };
    NotionPiPBridge?: {
      snapshot(): EditorSnapshot;
      applyNativeReply(reply: unknown): boolean;
      restore(draftID: string, expectedRevision: number): Promise<BridgeReply>;
      resolveConflict(action: ConflictAction, operationID: string): Promise<BridgeReply>;
      retryPendingTransition(): Promise<BridgeReply>;
      prefill(text: string): boolean;
    };
  }
}

interface OverlayTransactionChanges {
  readonly docChanged: boolean;
  readonly selectionSet: boolean;
  readonly storedMarksSet: boolean;
}

export function overlayRefreshTargets(changes: OverlayTransactionChanges): {
  readonly slashMenu: boolean;
  readonly formattingToolbar: boolean;
} {
  return {
    slashMenu: changes.docChanged || changes.selectionSet,
    formattingToolbar: changes.docChanged
      || changes.selectionSet
      || changes.storedMarksSet,
  };
}

export class QuickCaptureEditorController {
  private snapshot: EditorSnapshot = {
    draftID: "",
    title: "",
    revision: 0,
    document: normalizeDocument(null),
  };
  private applyingNativeSnapshot = false;
  private transitionLocked = true;
  private pendingLaunchFocus: "title" | "body" | undefined;
  private pendingPrefill: string | undefined;
  private autosaveRetryAvailable = false;
  private transitionRetryAvailable = false;
  private started = false;

  private readonly elements: QuickCaptureEditorElements;
  private readonly client: BridgeClient;
  private readonly editor: Editor;
  private readonly changes: DebouncedChangePublisher;
  private readonly transitions: EditorTransitionGate;
  private readonly slashMenu: SlashMenuController;
  private readonly formattingToolbar: FormattingToolbarController;

  constructor(bridge: NativeCaptureBridge, elements: QuickCaptureEditorElements) {
    this.elements = elements;
    this.client = new BridgeClient((request) => bridge.postMessage(request));
    this.slashMenu = new SlashMenuController(elements.slashMenu, elements.page);
    this.formattingToolbar = new FormattingToolbarController(
      elements.formatToolbar,
      elements.page,
    );
    this.editor = new Editor({
      element: elements.editor,
      extensions: [
        StarterKit.configure({
          link: {
            openOnClick: false,
            linkOnPaste: false,
          },
        }),
        Placeholder.configure({ placeholder: "Type '/' for commands" }),
        TaskList,
        TaskItem.configure({ nested: true }),
      ],
      content: this.snapshot.document as JSONContent,
      editorProps: {
        attributes: {
          role: "textbox",
          "aria-label": "Note content",
          "aria-multiline": "true",
          "aria-controls": "slash-menu",
          "aria-expanded": "false",
          "aria-haspopup": "listbox",
        },
        handleKeyDown: (view, event) => this.handleEditorKeyDown(view, event),
        handlePaste: (view, event) => {
          const { selection } = view.state;
          const text = event.clipboardData?.getData("text/plain") ?? "";
          const selectedText = view.state.doc.textBetween(selection.from, selection.to);
          if (selectedText.length === 0 || !isLinkPaste(selection, text)) return false;
          return this.editor.chain().focus().setLink({ href: text.trim() }).run();
        },
      },
      autofocus: false,
      editable: false,
      onTransaction: ({ editor, transaction }) => {
        const targets = overlayRefreshTargets(transaction);
        if (targets.slashMenu) {
          this.slashMenu.refresh(editor, this.transitionLocked);
        }
        if (targets.formattingToolbar) {
          this.formattingToolbar.refresh(editor, this.transitionLocked);
        }
      },
      onFocus: ({ editor }) => {
        this.formattingToolbar.refresh(editor, this.transitionLocked);
      },
      onBlur: ({ editor }) => {
        this.slashMenu.close(editor);
        this.formattingToolbar.handleEditorBlur(editor);
      },
      onUpdate: () => {
        this.scheduleChange();
      },
    });
    this.changes = new DebouncedChangePublisher(
      300,
      async (request) => {
        const reply = await this.client.dispatch(request);
        this.applyReply(reply);
        requireAutosaveAcknowledgement(reply);
      },
      () => crypto.randomUUID(),
      (error) => this.reportFailure(error),
      (available) => {
        this.autosaveRetryAvailable = available;
        this.refreshRetryAvailability();
      },
    );
    this.transitions = new EditorTransitionGate(
      this.changes,
      (request) => this.client.dispatch(request),
      (reply) => this.applyReply(reply),
      (locked) => {
        this.transitionLocked = locked;
        this.refreshMutationControls();
        this.applyPendingPrefill();
        this.applyPendingLaunchFocus();
      },
      (available) => {
        this.transitionRetryAvailable = available;
        this.refreshRetryAvailability();
      },
    );
    this.formattingToolbar.bind(this.editor, () => this.transitionLocked);
    this.bindControls();
    this.installBridgeSurface();
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    void this.transitions.perform({
      key: "ready",
      expectedKind: "ready",
      drainPendingChanges: false,
      unlockOnDefinitiveRejection: false,
      makeRequest: () => makeRequest("ready", crypto.randomUUID(), {}),
    }).catch((error) => this.reportFailure(error));
  }

  private handleEditorKeyDown(
    view: Editor["view"],
    event: KeyboardEvent,
  ): boolean {
    if (isCompositionKey(event)) return false;
    if (this.formattingToolbar.handleEditorKeyDown(this.editor, event)) return true;
    if (this.slashMenu.handleKeyDown(this.editor, event)) return true;

    const { empty, from } = view.state.selection;
    let caretPosition = empty ? from : undefined;
    const domSelection = view.dom.ownerDocument.getSelection();
    if (domSelection?.anchorNode !== null
        && domSelection?.anchorNode !== undefined
        && view.dom.contains(domSelection.anchorNode)) {
      caretPosition = domSelection.isCollapsed
        ? view.posAtDOM(domSelection.anchorNode, domSelection.anchorOffset)
        : undefined;
    }
    let firstTextBlockStart: number | undefined;
    view.state.doc.descendants((node, position) => {
      if (firstTextBlockStart !== undefined) return false;
      if (!node.isTextblock) return true;
      firstTextBlockStart = position + 1;
      return false;
    });
    const isAtStartOfFirstBlock = caretPosition === firstTextBlockStart;
    if (event.key !== "ArrowUp" || !isAtStartOfFirstBlock) return false;
    event.preventDefault();
    this.elements.title.focus();
    this.elements.title.setSelectionRange(
      this.elements.title.value.length,
      this.elements.title.value.length,
    );
    return true;
  }

  private bindControls(): void {
    this.elements.title.addEventListener("input", () => {
      this.scheduleChange();
    });
    this.elements.title.addEventListener("keydown", (event) => {
      const atBoundary = this.elements.title.selectionStart === this.elements.title.value.length
        && this.elements.title.selectionEnd === this.elements.title.value.length;
      if (routeTitleKey({
        key: event.key,
        atBoundary,
        shiftKey: event.shiftKey,
        isComposing: event.isComposing,
        keyCode: event.keyCode,
      }) !== "focusBody") {
        return;
      }
      event.preventDefault();
      this.focusBody("start");
    });
    this.elements.newNoteButton?.addEventListener("click", () => {
      void this.transitions.perform({
        key: "stash",
        expectedKind: "stashed",
        makeRequest: () => makeRequest("stash", crypto.randomUUID(), {
          snapshot: {
            draftID: this.snapshot.draftID,
            title: this.elements.title.value,
            document: normalizeDocument(this.editor.getJSON()),
          },
          expectedRevision: this.snapshot.revision ?? 0,
        }),
      }).catch((error) => this.reportFailure(error));
    });
    this.elements.retryButton?.addEventListener("click", () => {
      const retry = this.transitions.hasPendingTransition
        ? this.transitions.retryPending()
        : this.changes.retryFailed();
      void retry.catch((error) => this.reportFailure(error));
    });
  }

  private installBridgeSurface(): void {
    window.NotionPiPBridge = {
      snapshot: () => ({
        draftID: this.snapshot.draftID,
        title: this.elements.title.value,
        revision: this.snapshot.revision ?? 0,
        document: normalizeDocument(this.editor.getJSON()),
      }),
      prefill: (text) => {
        if (text.length === 0) return false;
        this.pendingPrefill = text;
        this.applyPendingPrefill();
        return true;
      },
      applyNativeReply: (reply) => {
        if (!isBridgeReply(reply)) return false;
        this.applyReply(reply);
        return true;
      },
      restore: (draftID, expectedRevision) => this.transitions
        .perform({
          key: `restore:${draftID}:${expectedRevision}`,
          expectedKind: "restored",
          retainTerminalReceipt: true,
          makeRequest: () => makeRequest(
            "restore",
            crypto.randomUUID(),
            { draftID, expectedRevision },
          ),
        })
        .catch((error) => {
          this.reportFailure(error);
          throw error;
        }),
      resolveConflict: (action, operationID) => this.transitions.perform(
        conflictTransitionOperation(action, operationID, () => ({
          draftID: this.snapshot.draftID,
          title: this.elements.title.value,
          document: normalizeDocument(this.editor.getJSON()),
        })),
      ).then((reply) => {
        if (!reply.ok) throw new Error(reply.error.message);
        return reply;
      }).catch((error) => {
        this.reportFailure(error);
        throw error;
      }),
      retryPendingTransition: () => this.transitions.retryPending(),
    };
  }

  private scheduleChange(): void {
    if (this.applyingNativeSnapshot
        || this.transitionLocked
        || this.snapshot.draftID.length === 0) return;
    this.elements.status.dataset.state = "saving";
    this.elements.status.textContent = "Saving…";
    this.changes.changed(
      () => ({
        draftID: this.snapshot.draftID,
        title: this.elements.title.value,
        document: this.editor.getJSON(),
      }),
      () => this.snapshot.revision ?? 0,
    );
  }

  private refreshRetryAvailability(): void {
    if (this.elements.retryButton !== null) {
      this.elements.retryButton.hidden = !this.autosaveRetryAvailable
        && !this.transitionRetryAvailable;
    }
  }

  private focusBody(position: "start" | "end"): void {
    this.editor.commands.focus(position, { scrollIntoView: false });
    this.editor.view.focus();
  }

  private applyPendingPrefill(): void {
    const text = this.pendingPrefill;
    if (text === undefined || this.transitionLocked) return;
    this.pendingPrefill = undefined;
    if (this.editor.isEmpty) {
      this.editor.commands.setContent({ type: "doc", content: [{
        type: "paragraph", content: [{ type: "text", text }],
      }] });
      this.focusBody("end");
    } else {
      this.editor.chain().focus("end").insertContent(`\n${text}`).run();
    }
  }

  private installSnapshot(next: EditorSnapshot): boolean {
    if (!canInstallSnapshot(this.snapshot, next)) return true;
    this.applyingNativeSnapshot = true;
    this.snapshot = next;
    this.elements.title.value = next.title;
    this.editor.commands.setContent(normalizeDocument(next.document) as JSONContent);
    this.applyingNativeSnapshot = false;
    return true;
  }

  private applyReply(reply: BridgeReply): boolean {
    if (reply.ok) {
      if (reply.result.snapshot !== undefined) {
        const installsSnapshot = canInstallSnapshot(this.snapshot, reply.result.snapshot);
        this.installSnapshot(reply.result.snapshot);
        if (reply.result.kind === "ready") {
          this.pendingLaunchFocus = this.elements.title.value.trim().length === 0
            && this.editor.isEmpty
            ? "title"
            : "body";
        } else if (reply.result.kind === "stashed" && installsSnapshot) {
          this.slashMenu.close(this.editor);
          this.formattingToolbar.close();
          this.pendingLaunchFocus = "title";
        }
      } else if (reply.result.revision !== undefined) {
        this.snapshot.revision = Math.max(
          this.snapshot.revision ?? 0,
          reply.result.revision,
        );
      }
      this.elements.status.dataset.state = "saved";
      this.elements.status.textContent = "Saved";
    } else {
      this.elements.status.dataset.state = "error";
      this.elements.status.textContent = reply.error.message;
    }
    return true;
  }

  private reportFailure(value: unknown): void {
    this.elements.status.dataset.state = "error";
    this.elements.status.textContent = value instanceof Error
      ? value.message
      : "The draft could not be saved.";
  }

  private refreshMutationControls(): void {
    this.elements.title.disabled = this.transitionLocked;
    this.editor.setEditable(!this.transitionLocked, false);
    if (this.elements.newNoteButton !== null) {
      this.elements.newNoteButton.disabled = this.transitionLocked;
    }
    this.formattingToolbar.setMutationLocked(this.transitionLocked);
    if (this.transitionLocked) this.slashMenu.close(this.editor);
  }

  private applyPendingLaunchFocus(): void {
    const target = this.pendingLaunchFocus;
    if (target === undefined || this.transitionLocked) return;
    this.pendingLaunchFocus = undefined;
    if (target === "title") this.elements.title.focus();
    else this.focusBody("end");
  }
}
