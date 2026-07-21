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
  type ConflictAction,
  type EditorSnapshot,
  type JSONValue,
} from "./protocol.ts";

export type ToolbarCommand = "bold" | "italic" | "heading" | "bulletList" | "orderedList";

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

  private async deliver(request: BridgeRequest): Promise<void> {
    try {
      await this.send(request);
      if (this.failedRequest === request) this.failedRequest = undefined;
    } catch (value) {
      const error = value instanceof Error ? value : new Error("Bridge delivery failed");
      this.failedRequest = request;
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
  if (!reply.ok
      && reply.error.code === "persistenceFailure"
      && reply.error.recoverable) {
    throw new Error(reply.error.message);
  }
  return reply;
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
  const saveButton = document.querySelector<HTMLButtonElement>("#save");
  const stashButton = document.querySelector<HTMLButtonElement>("#stash");
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
  let recoveryLocked = false;
  let userActionPending = false;
  const client = new BridgeClient((request) => bridge.postMessage(request));
  const editor = new Editor({
    element: editorElement,
    extensions: [StarterKit],
    content: snapshot.document as JSONContent,
    autofocus: "end",
    onUpdate: ({ editor: updatedEditor }) => {
      if (applyingNativeSnapshot || recoveryLocked || snapshot.draftID.length === 0) return;
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
  let conflictResolution: {
    action: ConflictAction;
    operationID: string;
    request: BridgeRequest;
  } | undefined;

  function installSnapshot(next: EditorSnapshot): void {
    applyingNativeSnapshot = true;
    snapshot = next;
    titleInput.value = next.title;
    editor.commands.setContent(normalizeDocument(next.document) as JSONContent);
    applyingNativeSnapshot = false;
  }

  function applyReply(reply: BridgeReply): void {
    if (reply.ok) {
      if (reply.result.snapshot !== undefined) installSnapshot(reply.result.snapshot);
      else if (reply.result.revision !== undefined) snapshot.revision = reply.result.revision;
      status.dataset.state = "saved";
      status.textContent = "Saved";
    } else {
      status.dataset.state = "error";
      status.textContent = reply.error.message;
    }
  }

  function reportFailure(value: unknown): void {
    status.dataset.state = "error";
    status.textContent = value instanceof Error ? value.message : "The draft could not be saved.";
  }

  function refreshMutationControls(): void {
    const disabled = recoveryLocked || userActionPending;
    titleInput.disabled = recoveryLocked;
    editor.setEditable(!recoveryLocked);
    if (saveButton !== null) saveButton.disabled = disabled;
    if (stashButton !== null) stashButton.disabled = disabled;
    formattingButtons.forEach((button) => { button.disabled = recoveryLocked; });
  }

  async function performUserAction<T>(action: () => Promise<T>): Promise<T> {
    userActionPending = true;
    refreshMutationControls();
    try {
      return await runAfterPendingChange(changes, action);
    } finally {
      userActionPending = false;
      refreshMutationControls();
    }
  }

  titleInput.addEventListener("input", () => {
    if (recoveryLocked || snapshot.draftID.length === 0) return;
    changes.changed(
      { draftID: snapshot.draftID, title: titleInput.value, document: normalizeDocument(editor.getJSON()) },
      () => snapshot.revision ?? 0,
    );
  });
  formattingButtons.forEach((button) => {
    button.addEventListener("click", () => executeToolbarCommand(editor, button.dataset.command ?? ""));
  });
  saveButton?.addEventListener("click", async () => {
    void performUserAction(() => client.request("save", {
      snapshot: {
        draftID: snapshot.draftID,
        title: titleInput.value,
        document: normalizeDocument(editor.getJSON()),
      },
      expectedRevision: snapshot.revision ?? 0,
    })).then(applyReply).catch(reportFailure);
  });
  stashButton?.addEventListener("click", async () => {
    void performUserAction(() => client.request("stash", {
      snapshot: {
        draftID: snapshot.draftID,
        title: titleInput.value,
        document: normalizeDocument(editor.getJSON()),
      },
      expectedRevision: snapshot.revision ?? 0,
    })).then(applyReply).catch(reportFailure);
  });

  window.NotionPiPBridge = {
    applyNativeReply: (reply) => {
      if (!isBridgeReply(reply)) return false;
      applyReply(reply);
      return true;
    },
    restore: (draftID, expectedRevision) => client
      .request("restore", { draftID, expectedRevision })
      .then((reply) => { applyReply(reply); return reply; })
      .catch((error) => { reportFailure(error); throw error; }),
    resolveConflict: (action, operationID) => runAfterPendingChange(changes, async () => {
      recoveryLocked = true;
      refreshMutationControls();
      try {
        // An edit can arrive while the action's first flush is awaiting native I/O.
        // Lock first, then drain once more so the final live snapshot has no queued predecessor.
        await changes.flush();
        if (conflictResolution?.operationID === operationID) {
          if (conflictResolution.action !== action) {
            throw new Error("Conflict recovery operation does not match its original action");
          }
        } else {
          conflictResolution = {
            action,
            operationID,
            request: makeRequest("resolveConflict", operationID, {
              action,
              snapshot: {
                draftID: snapshot.draftID,
                title: titleInput.value,
                document: normalizeDocument(editor.getJSON()),
              },
            }),
          };
        }
        const reply = await client.dispatch(conflictResolution.request);
        applyReply(reply);
        if (!reply.ok) throw new Error(reply.error.message);
        return reply;
      } finally {
        recoveryLocked = false;
        refreshMutationControls();
      }
    }).catch((error) => {
      reportFailure(error);
      throw error;
    }),
  };

  void client.request("ready", {}).then(applyReply).catch(reportFailure);
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
