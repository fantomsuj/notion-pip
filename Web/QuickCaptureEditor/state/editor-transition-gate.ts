import { AutosaveAcknowledgementError, type DebouncedChangePublisher } from "../bridge/debounced-change-publisher.ts";
import {
  isBridgeReply,
  makeRequest,
  type BridgeReply,
  type BridgeRequest,
  type BridgeResultKind,
  type ConflictAction,
  type EditorSnapshot,
} from "../protocol.ts";

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
