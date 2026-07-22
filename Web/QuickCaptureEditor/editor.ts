import { Editor } from "@tiptap/core";
import type { JSONContent } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";

import {
  BRIDGE_VERSION,
  isBridgeReply,
  makeRequest,
  type BridgeReply,
  type BridgeRequest,
  type BridgeRequestPayload,
  type BridgeResultKind,
  type ConflictAction,
  type EditorSnapshot,
  type JSONValue,
} from "./protocol.ts";

export type ToolbarCommand = "bold" | "italic" | "heading" | "bulletList" | "orderedList";

export type BlockCommandID =
  | "text"
  | "heading1"
  | "heading2"
  | "heading3"
  | "bulletList"
  | "orderedList"
  | "taskList"
  | "quote"
  | "codeBlock"
  | "divider";

export type TiptapBlockCommand =
  | "setParagraph"
  | "toggleHeading"
  | "toggleBulletList"
  | "toggleOrderedList"
  | "toggleTaskList"
  | "toggleBlockquote"
  | "toggleCodeBlock"
  | "setHorizontalRule";

export interface BlockCommand {
  readonly id: BlockCommandID;
  readonly label: string;
  readonly aliases: readonly string[];
  readonly command: TiptapBlockCommand;
}

export const BLOCK_COMMANDS: readonly BlockCommand[] = [
  { id: "text", label: "Text", aliases: ["paragraph", "plain text"], command: "setParagraph" },
  { id: "heading1", label: "Heading 1", aliases: ["h1", "title"], command: "toggleHeading" },
  { id: "heading2", label: "Heading 2", aliases: ["h2", "subtitle"], command: "toggleHeading" },
  { id: "heading3", label: "Heading 3", aliases: ["h3", "subheading"], command: "toggleHeading" },
  {
    id: "bulletList",
    label: "Bulleted list",
    aliases: ["bullet", "unordered", "ul"],
    command: "toggleBulletList",
  },
  {
    id: "orderedList",
    label: "Numbered list",
    aliases: ["numbered", "ordered", "ol"],
    command: "toggleOrderedList",
  },
  {
    id: "taskList",
    label: "To-do list",
    aliases: ["todo", "task", "checklist"],
    command: "toggleTaskList",
  },
  { id: "quote", label: "Quote", aliases: ["blockquote", "citation"], command: "toggleBlockquote" },
  { id: "codeBlock", label: "Code block", aliases: ["code", "preformatted"], command: "toggleCodeBlock" },
  {
    id: "divider",
    label: "Divider",
    aliases: ["horizontal rule", "separator", "hr"],
    command: "setHorizontalRule",
  },
];

export function filterBlockCommands(query: string): readonly BlockCommand[] {
  const normalizedQuery = query.trim().toLocaleLowerCase();
  if (normalizedQuery.length === 0) return BLOCK_COMMANDS;
  return BLOCK_COMMANDS.filter((item) =>
    [item.label, ...item.aliases]
      .some((term) => term.toLocaleLowerCase().includes(normalizedQuery)),
  );
}

export function displayTitle(title: string): string {
  return title.trim().length === 0 ? "Untitled" : title;
}

export type TitleRoute = "focusBody" | "none";

export interface TitleKeyInput {
  readonly key: string;
  readonly atBoundary: boolean;
}

export function routeTitleKey(input: TitleKeyInput): TitleRoute {
  if (input.key === "Enter" || input.key === "Tab") return "focusBody";
  if (input.key === "ArrowDown" && input.atBoundary) return "focusBody";
  return "none";
}

export type OverlayRoute = "previous" | "next" | "select" | "dismiss" | "none";

export interface OverlayKeyInput {
  readonly key: string;
  readonly isOpen: boolean;
}

export function routeOverlayKey(input: OverlayKeyInput): OverlayRoute {
  if (!input.isOpen) return "none";
  switch (input.key) {
    case "ArrowUp": return "previous";
    case "ArrowDown": return "next";
    case "Enter": return "select";
    case "Escape": return "dismiss";
    default: return "none";
  }
}

export interface EditorCommandTarget {
  focus(): EditorCommandTarget;
  toggleBold(): EditorCommandTarget;
  toggleItalic(): EditorCommandTarget;
  toggleHeading(options: { level: 2 }): EditorCommandTarget;
  toggleBulletList(): EditorCommandTarget;
  toggleOrderedList(): EditorCommandTarget;
  run(): boolean;
}

export interface ChainableEditor {
  chain(): EditorCommandTarget;
}

export function normalizeDocument(value: unknown): JSONValue {
  if (!isRecord(value) || value.type !== "doc" || !Array.isArray(value.content) || value.content.length === 0) {
    return { type: "doc", content: [{ type: "paragraph" }] };
  }
  return canonicalize(value) as JSONValue;
}

export function executeToolbarCommand(editor: ChainableEditor, command: string): boolean {
  const chain = editor.chain().focus();
  switch (command) {
    case "bold": return chain.toggleBold().run();
    case "italic": return chain.toggleItalic().run();
    case "heading": return chain.toggleHeading({ level: 2 }).run();
    case "bulletList": return chain.toggleBulletList().run();
    case "orderedList": return chain.toggleOrderedList().run();
    default: return false;
  }
}

export class DebouncedChangePublisher {
  private timer: ReturnType<typeof setTimeout> | undefined;
  private pending: {
    snapshot: Omit<EditorSnapshot, "revision">;
    expectedRevision: () => number;
  } | undefined;
  private deliveryTail: Promise<void> = Promise.resolve();
  private actionTail: Promise<void> = Promise.resolve();
  private failedRequest: BridgeRequest | undefined;
  private readonly delayMilliseconds: number;
  private readonly send: (request: BridgeRequest) => void | Promise<void>;
  private readonly nextID: () => string;
  private readonly onDeliveryError: (error: Error) => void;

  constructor(
    delayMilliseconds: number,
    send: (request: BridgeRequest) => void | Promise<void>,
    nextID: () => string = () => crypto.randomUUID(),
    onDeliveryError: (error: Error) => void = () => {},
  ) {
    this.delayMilliseconds = delayMilliseconds;
    this.send = send;
    this.nextID = nextID;
    this.onDeliveryError = onDeliveryError;
  }

  changed(
    snapshot: Omit<EditorSnapshot, "revision">,
    expectedRevision: number | (() => number),
  ): void {
    this.pending = {
      snapshot: { ...snapshot, document: normalizeDocument(snapshot.document) },
      expectedRevision: typeof expectedRevision === "number" ? () => expectedRevision : expectedRevision,
    };
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = setTimeout(() => { void this.flush().catch(() => {}); }, this.delayMilliseconds);
  }

  async flush(): Promise<void> {
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
    const pending = this.pending;
    this.pending = undefined;
    let pendingRequestCreated = false;
    const delivery = this.deliveryTail.then(async () => {
      if (this.failedRequest !== undefined) {
        await this.deliver(this.failedRequest);
      }
      if (pending !== undefined) {
        const request = makeRequest("changed", this.nextID(), {
          snapshot: pending.snapshot,
          expectedRevision: pending.expectedRevision(),
        });
        pendingRequestCreated = true;
        await this.deliver(request);
      }
    }).catch((error) => {
      if (pending !== undefined && !pendingRequestCreated && this.pending === undefined) {
        this.pending = pending;
      }
      throw error;
    });
    this.deliveryTail = delivery.catch(() => {});
    await delivery;
  }

  async performAfterPendingChange<T>(action: () => Promise<T>): Promise<T> {
    const operation = this.actionTail.then(async () => {
      await this.flush();
      return action();
    });
    this.actionTail = operation.then(() => {}, () => {});
    return operation;
  }

  discardPending(): void {
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
    this.pending = undefined;
    this.failedRequest = undefined;
  }

  private async deliver(request: BridgeRequest): Promise<void> {
    try {
      await this.send(request);
      if (this.failedRequest === request) this.failedRequest = undefined;
    } catch (value) {
      const error = value instanceof Error ? value : new Error("Bridge delivery failed");
      if (error instanceof AutosaveAcknowledgementError && error.abortsPendingTransition) {
        if (this.failedRequest === request) this.failedRequest = undefined;
      } else {
        this.failedRequest = request;
      }
      this.onDeliveryError(error);
      throw error;
    }
  }
}

export async function runAfterPendingChange<T>(
  publisher: DebouncedChangePublisher,
  action: () => Promise<T>,
): Promise<T> {
  return publisher.performAfterPendingChange(action);
}

export function requireAutosaveAcknowledgement(reply: BridgeReply): BridgeReply {
  if (!reply.ok) {
    throw new AutosaveAcknowledgementError(
      reply.error.message,
      reply.error.code === "staleRevision",
    );
  }
  return reply;
}

class AutosaveAcknowledgementError extends Error {
  readonly abortsPendingTransition: boolean;

  constructor(message: string, abortsPendingTransition: boolean) {
    super(message);
    this.name = "AutosaveAcknowledgementError";
    this.abortsPendingTransition = abortsPendingTransition;
  }
}

export class BridgeClient {
  private readonly send: (request: BridgeRequest) => Promise<unknown>;
  private readonly nextID: () => string;
  private readonly timeoutMilliseconds: number;

  constructor(
    send: (request: BridgeRequest) => Promise<unknown>,
    nextID: () => string = () => crypto.randomUUID(),
    timeoutMilliseconds = 5_000,
  ) {
    this.send = send;
    this.nextID = nextID;
    this.timeoutMilliseconds = timeoutMilliseconds;
  }

  async request<T extends BridgeRequest["type"]>(
    type: T,
    payload: BridgeRequestPayload<T>,
  ): Promise<BridgeReply> {
    const id = this.nextID();
    const request = makeRequest(type, id, payload);
    return this.dispatch(request);
  }

  async dispatch(request: BridgeRequest): Promise<BridgeReply> {
    let timeout: ReturnType<typeof setTimeout> | undefined;
    const value = await Promise.race([
      this.send(request),
      new Promise<never>((_resolve, reject) => {
        timeout = setTimeout(
          () => reject(new Error("Native bridge acknowledgement timed out")),
          this.timeoutMilliseconds,
        );
      }),
    ]).finally(() => {
      if (timeout !== undefined) clearTimeout(timeout);
    });
    if (!isBridgeReply(value)) throw new Error("Malformed bridge reply");
    if (value.id !== request.id) throw new Error("Bridge reply correlation ID mismatch");
    return value;
  }
}

export interface EditorTransitionOperation {
  key: string;
  expectedKind: BridgeResultKind;
  makeRequest: () => BridgeRequest;
  drainPendingChanges?: boolean;
  discardPendingChanges?: boolean;
  unlockOnDefinitiveRejection?: boolean;
  retainTerminalReceipt?: boolean;
}

export function conflictTransitionOperation(
  action: ConflictAction,
  operationID: string,
  snapshot: () => Omit<EditorSnapshot, "revision">,
): EditorTransitionOperation {
  return {
    key: `conflict:${operationID}:${action}`,
    expectedKind: "conflictResolved",
    drainPendingChanges: false,
    discardPendingChanges: true,
    retainTerminalReceipt: true,
    makeRequest: () => makeRequest("resolveConflict", operationID, {
      action,
      snapshot: snapshot(),
    }),
  };
}

interface PendingEditorTransition extends EditorTransitionOperation {
  request?: BridgeRequest;
}

export class EditorTransitionGate {
  private pending: PendingEditorTransition | undefined;
  private operationTail: Promise<void> = Promise.resolve();
  private locked = true;
  private readonly terminalReceipts = new Map<
    string,
    { expectedKind: BridgeResultKind; reply: BridgeReply }
  >();
  private readonly changes: DebouncedChangePublisher;
  private readonly dispatch: (request: BridgeRequest) => Promise<unknown>;
  private readonly applyReply: (reply: BridgeReply) => boolean;
  private readonly onLockChanged: (locked: boolean) => void;
  private readonly onRetryAvailabilityChanged: (available: boolean) => void;

  constructor(
    changes: DebouncedChangePublisher,
    dispatch: (request: BridgeRequest) => Promise<unknown>,
    applyReply: (reply: BridgeReply) => boolean,
    onLockChanged: (locked: boolean) => void,
    onRetryAvailabilityChanged: (available: boolean) => void = () => {},
  ) {
    this.changes = changes;
    this.dispatch = dispatch;
    this.applyReply = applyReply;
    this.onLockChanged = onLockChanged;
    this.onRetryAvailabilityChanged = onRetryAvailabilityChanged;
    this.onLockChanged(true);
  }

  get isLocked(): boolean {
    return this.locked;
  }

  get hasPendingTransition(): boolean {
    return this.pending !== undefined;
  }

  async perform(operation: EditorTransitionOperation): Promise<BridgeReply> {
    const execution = this.operationTail.then(() => this.execute(operation));
    this.operationTail = execution.then(() => {}, () => {});
    return execution;
  }

  async retryPending(): Promise<BridgeReply> {
    const pending = this.pending;
    if (pending === undefined) throw new Error("There is no pending transition to retry");
    return this.perform(pending);
  }

  private async execute(operation: EditorTransitionOperation): Promise<BridgeReply> {
    if (this.pending !== undefined && this.pending.key !== operation.key) {
      throw new Error("A pending transition must be acknowledged before another operation");
    }
    const terminal = this.terminalReceipts.get(operation.key);
    if (terminal !== undefined) {
      if (terminal.expectedKind !== operation.expectedKind) {
        throw new Error("Terminal transition receipt does not match the requested result kind");
      }
      return terminal.reply;
    }
    this.setLocked(true);
    this.pending ??= { ...operation };
    const pending = this.pending;

    try {
      if (pending.request === undefined) {
        if (pending.discardPendingChanges === true) this.changes.discardPending();
        if (pending.drainPendingChanges !== false) await this.changes.flush();
        pending.request = pending.makeRequest();
      }
      const value = await this.dispatch(pending.request);
      if (!isBridgeReply(value) || value.id !== pending.request.id) {
        throw new Error("Malformed bridge reply for state transition");
      }
      if (value.ok) {
        if (value.result.kind !== pending.expectedKind) {
          throw new Error("Unexpected bridge result for state transition");
        }
        if (!this.applyReply(value)) {
          throw new Error("State transition reply could not be applied");
        }
        this.completePendingTransition(value);
        return value;
      }

      this.applyReply(value);
      if (value.error.code !== "persistenceFailure"
          && pending.unlockOnDefinitiveRejection !== false) {
        this.completePendingTransition();
        return value;
      }
      throw new Error(value.error.message);
    } catch (error) {
      if (error instanceof AutosaveAcknowledgementError
          && error.abortsPendingTransition
          && pending.request === undefined) {
        this.completePendingTransition();
      } else {
        this.onRetryAvailabilityChanged(true);
      }
      throw error;
    }
  }

  private completePendingTransition(reply?: BridgeReply): void {
    const completed = this.pending;
    if (reply !== undefined && completed?.retainTerminalReceipt === true) {
      this.terminalReceipts.set(completed.key, {
        expectedKind: completed.expectedKind,
        reply,
      });
      while (this.terminalReceipts.size > 64) {
        const oldest = this.terminalReceipts.keys().next().value as string | undefined;
        if (oldest === undefined) break;
        this.terminalReceipts.delete(oldest);
      }
    }
    this.pending = undefined;
    this.onRetryAvailabilityChanged(false);
    this.setLocked(false);
  }

  private setLocked(locked: boolean): void {
    if (this.locked === locked) return;
    this.locked = locked;
    this.onLockChanged(locked);
  }
}

export function canInstallSnapshot(current: EditorSnapshot, next: EditorSnapshot): boolean {
  if (current.draftID !== next.draftID) return true;
  const currentRevision = current.revision ?? 0;
  const nextRevision = next.revision ?? 0;
  return nextRevision >= currentRevision;
}

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        captureBridge?: { postMessage(request: BridgeRequest): Promise<unknown> };
      };
    };
    NotionPiPBridge?: {
      applyNativeReply(reply: unknown): boolean;
      restore(draftID: string, expectedRevision: number): Promise<BridgeReply>;
      resolveConflict(action: ConflictAction, operationID: string): Promise<BridgeReply>;
      retryPendingTransition(): Promise<BridgeReply>;
    };
  }
}

function bootstrap(): void {
  const bridge = window.webkit?.messageHandlers?.captureBridge;
  const editorElement = document.querySelector<HTMLElement>("#editor");
  const titleElement = document.querySelector<HTMLInputElement>("#title");
  const statusElement = document.querySelector<HTMLElement>("#status");
  if (bridge === undefined || editorElement === null || titleElement === null || statusElement === null) return;
  const titleInput = titleElement;
  const status = statusElement;
  const newNoteButton = document.querySelector<HTMLButtonElement>("#new-note");
  const retryButton = document.querySelector<HTMLButtonElement>("#retry");
  const formattingButtons = Array.from(
    document.querySelectorAll<HTMLButtonElement>("[data-command]"),
  );

  let snapshot: EditorSnapshot = {
    draftID: "",
    title: "",
    revision: 0,
    document: normalizeDocument(null),
  };
  let applyingNativeSnapshot = false;
  let transitionLocked = true;
  let pendingLaunchFocus: "title" | "body" | undefined;
  const client = new BridgeClient((request) => bridge.postMessage(request));
  const editor = new Editor({
    element: editorElement,
    extensions: [StarterKit],
    content: snapshot.document as JSONContent,
    editorProps: {
      attributes: {
        role: "textbox",
        "aria-label": "Note content",
        "aria-multiline": "true",
      },
      handleKeyDown: (view, event) => {
        const { $from, empty } = view.state.selection;
        const isAtStartOfFirstBlock = empty
          && $from.depth === 1
          && $from.index(0) === 0
          && $from.parentOffset === 0;
        if (event.key !== "ArrowUp" || !isAtStartOfFirstBlock) return false;
        event.preventDefault();
        titleInput.focus();
        titleInput.setSelectionRange(titleInput.value.length, titleInput.value.length);
        return true;
      },
    },
    autofocus: false,
    editable: false,
    onUpdate: ({ editor: updatedEditor }) => {
      if (applyingNativeSnapshot || transitionLocked || snapshot.draftID.length === 0) return;
      status.dataset.state = "saving";
      status.textContent = "Saving…";
      changes.changed(
        {
          draftID: snapshot.draftID,
          title: titleInput.value,
          document: normalizeDocument(updatedEditor.getJSON()),
        },
        () => snapshot.revision ?? 0,
      );
    },
  });
  const changes = new DebouncedChangePublisher(
    300,
    async (request) => {
      const reply = await client.dispatch(request);
      applyReply(reply);
      requireAutosaveAcknowledgement(reply);
    },
    () => crypto.randomUUID(),
    (error) => reportFailure(error),
  );
  function focusBody(position: "start" | "end"): void {
    editor.commands.focus(position, { scrollIntoView: false });
    editor.view.focus();
  }

  function installSnapshot(next: EditorSnapshot): boolean {
    if (!canInstallSnapshot(snapshot, next)) return true;
    applyingNativeSnapshot = true;
    snapshot = next;
    titleInput.value = next.title;
    editor.commands.setContent(normalizeDocument(next.document) as JSONContent);
    applyingNativeSnapshot = false;
    return true;
  }

  function applyReply(reply: BridgeReply): boolean {
    if (reply.ok) {
      if (reply.result.snapshot !== undefined) {
        installSnapshot(reply.result.snapshot);
        if (reply.result.kind === "ready") {
          pendingLaunchFocus = titleInput.value.trim().length === 0 && editor.isEmpty
            ? "title"
            : "body";
        }
      }
      else if (reply.result.revision !== undefined) {
        snapshot.revision = Math.max(snapshot.revision ?? 0, reply.result.revision);
      }
      status.dataset.state = "saved";
      status.textContent = "Saved";
    } else {
      status.dataset.state = "error";
      status.textContent = reply.error.message;
    }
    return true;
  }

  function reportFailure(value: unknown): void {
    status.dataset.state = "error";
    status.textContent = value instanceof Error ? value.message : "The draft could not be saved.";
  }

  function refreshMutationControls(): void {
    titleInput.disabled = transitionLocked;
    editor.setEditable(!transitionLocked);
    if (newNoteButton !== null) newNoteButton.disabled = transitionLocked;
    formattingButtons.forEach((button) => { button.disabled = transitionLocked; });
  }

  function applyPendingLaunchFocus(): void {
    const target = pendingLaunchFocus;
    if (target === undefined || transitionLocked) return;
    pendingLaunchFocus = undefined;
    if (target === "title") titleInput.focus();
    else focusBody("end");
  }

  const transitions = new EditorTransitionGate(
    changes,
    (request) => client.dispatch(request),
    applyReply,
    (locked) => {
      transitionLocked = locked;
      refreshMutationControls();
      applyPendingLaunchFocus();
    },
    (available) => {
      if (retryButton !== null) retryButton.hidden = !available;
    },
  );

  titleInput.addEventListener("input", () => {
    if (transitionLocked || snapshot.draftID.length === 0) return;
    changes.changed(
      { draftID: snapshot.draftID, title: titleInput.value, document: normalizeDocument(editor.getJSON()) },
      () => snapshot.revision ?? 0,
    );
  });
  titleInput.addEventListener("keydown", (event) => {
    const atBoundary = titleInput.selectionStart === titleInput.value.length
      && titleInput.selectionEnd === titleInput.value.length;
    if (routeTitleKey({ key: event.key, atBoundary }) !== "focusBody") return;
    event.preventDefault();
    focusBody("start");
  });
  formattingButtons.forEach((button) => {
    button.addEventListener("click", () => executeToolbarCommand(editor, button.dataset.command ?? ""));
  });
  newNoteButton?.addEventListener("click", async () => {
    void transitions.perform({
      key: "stash",
      expectedKind: "stashed",
      makeRequest: () => makeRequest("stash", crypto.randomUUID(), {
        snapshot: {
          draftID: snapshot.draftID,
          title: titleInput.value,
          document: normalizeDocument(editor.getJSON()),
        },
        expectedRevision: snapshot.revision ?? 0,
      }),
    }).catch(reportFailure);
  });
  retryButton?.addEventListener("click", () => {
    void transitions.retryPending().catch(reportFailure);
  });

  window.NotionPiPBridge = {
    applyNativeReply: (reply) => {
      if (!isBridgeReply(reply)) return false;
      applyReply(reply);
      return true;
    },
    restore: (draftID, expectedRevision) => transitions
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
      .catch((error) => { reportFailure(error); throw error; }),
    resolveConflict: (action, operationID) => transitions.perform(
      conflictTransitionOperation(action, operationID, () => ({
        draftID: snapshot.draftID,
        title: titleInput.value,
        document: normalizeDocument(editor.getJSON()),
      })),
    ).then((reply) => {
      if (!reply.ok) throw new Error(reply.error.message);
      return reply;
    }).catch((error) => {
      reportFailure(error);
      throw error;
    }),
    retryPendingTransition: () => transitions.retryPending(),
  };

  void transitions.perform({
    key: "ready",
    expectedKind: "ready",
    drainPendingChanges: false,
    unlockOnDefinitiveRejection: false,
    makeRequest: () => makeRequest("ready", crypto.randomUUID(), {}),
  }).catch(reportFailure);
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!isRecord(value)) return value;
  const result: Record<string, unknown> = {};
  for (const key of Object.keys(value).sort()) {
    if (value[key] !== undefined) result[key] = canonicalize(value[key]);
  }
  return result;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

if (typeof document !== "undefined") {
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bootstrap, { once: true });
  else bootstrap();
}

export { BRIDGE_VERSION };
