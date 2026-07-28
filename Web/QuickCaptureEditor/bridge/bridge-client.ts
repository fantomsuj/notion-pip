import {
  isBridgeReply,
  makeRequest,
  type BridgeReply,
  type BridgeRequest,
  type BridgeRequestPayload,
} from "../protocol.ts";

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
