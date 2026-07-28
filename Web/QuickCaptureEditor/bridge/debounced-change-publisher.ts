import { normalizeDocument } from "../editor-state.ts";
import {
  makeRequest,
  type BridgeReply,
  type BridgeRequest,
  type EditorSnapshot,
} from "../protocol.ts";

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
  private readonly onRetryAvailabilityChanged: (available: boolean) => void;

  constructor(
    delayMilliseconds: number,
    send: (request: BridgeRequest) => void | Promise<void>,
    nextID: () => string = () => crypto.randomUUID(),
    onDeliveryError: (error: Error) => void = () => {},
    onRetryAvailabilityChanged: (available: boolean) => void = () => {},
  ) {
    this.delayMilliseconds = delayMilliseconds;
    this.send = send;
    this.nextID = nextID;
    this.onDeliveryError = onDeliveryError;
    this.onRetryAvailabilityChanged = onRetryAvailabilityChanged;
  }

  get hasFailedRequest(): boolean {
    return this.failedRequest !== undefined;
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

  async retryFailed(): Promise<void> {
    const request = this.failedRequest;
    if (request === undefined) throw new Error("There is no failed autosave to retry");
    const delivery = this.deliveryTail.then(async () => {
      if (this.failedRequest === request) await this.deliver(request);
    });
    this.deliveryTail = delivery.catch(() => {});
    await delivery;
  }

  discardPending(): void {
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
    this.pending = undefined;
    this.setFailedRequest(undefined);
  }

  private async deliver(request: BridgeRequest): Promise<void> {
    try {
      await this.send(request);
      if (this.failedRequest === request) this.setFailedRequest(undefined);
    } catch (value) {
      const error = value instanceof Error ? value : new Error("Bridge delivery failed");
      if (error instanceof AutosaveAcknowledgementError && error.abortsPendingTransition) {
        if (this.failedRequest === request) this.setFailedRequest(undefined);
      } else {
        this.setFailedRequest(request);
      }
      this.onDeliveryError(error);
      throw error;
    }
  }

  private setFailedRequest(request: BridgeRequest | undefined): void {
    const wasAvailable = this.failedRequest !== undefined;
    this.failedRequest = request;
    const isAvailable = request !== undefined;
    if (wasAvailable !== isAvailable) this.onRetryAvailabilityChanged(isAvailable);
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

export class AutosaveAcknowledgementError extends Error {
  readonly abortsPendingTransition: boolean;

  constructor(message: string, abortsPendingTransition: boolean) {
    super(message);
    this.name = "AutosaveAcknowledgementError";
    this.abortsPendingTransition = abortsPendingTransition;
  }
}
