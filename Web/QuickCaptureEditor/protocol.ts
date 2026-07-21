export const BRIDGE_VERSION = 1 as const;

export type JSONValue =
  | null
  | boolean
  | number
  | string
  | JSONValue[]
  | { [key: string]: JSONValue };

export interface EditorSnapshot {
  draftID: string;
  title: string;
  document: JSONValue;
  revision?: number;
}

interface RequestBase {
  version: typeof BRIDGE_VERSION;
  id: string;
}

export type ConflictAction = "reloadLatest" | "saveAsNew" | "openInNotion";

export type BridgeRequest =
  | (RequestBase & { type: "ready" })
  | (RequestBase & {
      type: "changed";
      snapshot: Omit<EditorSnapshot, "revision">;
      expectedRevision: number;
    })
  | (RequestBase & {
      type: "save";
      snapshot: Omit<EditorSnapshot, "revision">;
      expectedRevision: number;
    })
  | (RequestBase & {
      type: "stash";
      snapshot: Omit<EditorSnapshot, "revision">;
      expectedRevision: number;
    })
  | (RequestBase & { type: "restore"; draftID: string; expectedRevision: number })
  | (RequestBase & {
      type: "resolveConflict";
      action: ConflictAction;
      snapshot: Omit<EditorSnapshot, "revision">;
    });

export type BridgeResultKind =
  | "ready"
  | "changed"
  | "saved"
  | "stashed"
  | "restored"
  | "conflictResolved";

export interface BridgeSuccessReply {
  version: typeof BRIDGE_VERSION;
  id: string;
  ok: true;
  result: {
    kind: BridgeResultKind;
    revision?: number;
    snapshot?: EditorSnapshot;
  };
}

export interface BridgeErrorReply {
  version: typeof BRIDGE_VERSION;
  id: string;
  ok: false;
  error: {
    code: BridgeErrorCode;
    message: string;
    recoverable: boolean;
    latest?: EditorSnapshot;
  };
}

export type BridgeReply = BridgeSuccessReply | BridgeErrorReply;
export type BridgeErrorCode =
  | "invalidMessage"
  | "staleRevision"
  | "draftNotFound"
  | "persistenceFailure"
  | "unsupportedAction";

const requestTypes = new Set([
  "ready",
  "changed",
  "save",
  "stash",
  "restore",
  "resolveConflict",
]);

export function makeRequest(
  type: BridgeRequest["type"],
  id: string,
  payload: Record<string, unknown>,
): BridgeRequest {
  if (!requestTypes.has(type as string)) {
    throw new Error(`Unsupported bridge request: ${String(type)}`);
  }
  if (id.length === 0) {
    throw new Error("Bridge request ID must not be empty");
  }
  return { version: BRIDGE_VERSION, id, type, ...payload } as BridgeRequest;
}

export function isBridgeReply(value: unknown): value is BridgeReply {
  if (!isRecord(value)) return false;
  const baseKeys = value.ok === true
    ? new Set(["version", "id", "ok", "result"])
    : new Set(["version", "id", "ok", "error"]);
  if (!hasExactKeys(value, baseKeys)) return false;
  if (value.version !== BRIDGE_VERSION || !isBoundedString(value.id, 1, 128)) {
    return false;
  }
  if (value.ok === true) return isResult(value.result);
  if (value.ok === false) return isError(value.error);
  return false;
}

function isResult(value: unknown): boolean {
  if (!isRecord(value)) return false;
  switch (value.kind) {
    case "ready":
    case "stashed":
    case "restored":
      return hasExactKeys(value, new Set(["kind", "revision", "snapshot"]))
        && isRevision(value.revision)
        && isSnapshot(value.snapshot)
        && value.snapshot.revision === value.revision;
    case "changed":
    case "saved":
      return hasExactKeys(value, new Set(["kind", "revision"]))
        && isRevision(value.revision);
    case "conflictResolved": {
      if (hasExactKeys(value, new Set(["kind"]))) return true;
      return hasExactKeys(value, new Set(["kind", "revision", "snapshot"]))
        && isRevision(value.revision)
        && isSnapshot(value.snapshot)
        && value.snapshot.revision === value.revision;
    }
    default:
      return false;
  }
}

function isError(value: unknown): boolean {
  if (!isRecord(value)) return false;
  const fields = value.latest === undefined
    ? new Set(["code", "message", "recoverable"])
    : new Set(["code", "message", "recoverable", "latest"]);
  const codes = new Set<unknown>([
    "invalidMessage",
    "staleRevision",
    "draftNotFound",
    "persistenceFailure",
    "unsupportedAction",
  ]);
  return hasExactKeys(value, fields)
    && codes.has(value.code)
    && isBoundedString(value.message, 1, 32_768)
    && typeof value.recoverable === "boolean"
    && (value.code === "staleRevision" || value.latest === undefined)
    && (value.latest === undefined || isSnapshot(value.latest));
}

function isSnapshot(value: unknown): value is EditorSnapshot & { revision: number } {
  if (!isRecord(value)) return false;
  return hasExactKeys(value, new Set(["draftID", "title", "document", "revision"]))
    && isBoundedString(value.draftID, 1, 256)
    && value.draftID.trim().length > 0
    && isBoundedString(value.title, 0, 32_768)
    && isRevision(value.revision)
    && isDocument(value.document);
}

function isDocument(value: unknown): value is Record<string, JSONValue> {
  return isRecord(value)
    && hasExactKeys(value, new Set(["type", "content"]))
    && value.type === "doc"
    && Array.isArray(value.content);
}

function isRevision(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function isBoundedString(value: unknown, minimum: number, maximumUTF8Bytes: number): value is string {
  return typeof value === "string"
    && value.length >= minimum
    && new TextEncoder().encode(value).length <= maximumUTF8Bytes;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: Set<string>): boolean {
  const keys = Object.keys(value);
  return keys.length === expected.size && keys.every((key) => expected.has(key));
}
