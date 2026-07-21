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
    code: string;
    message: string;
    recoverable: boolean;
    latest?: EditorSnapshot;
  };
}

export type BridgeReply = BridgeSuccessReply | BridgeErrorReply;

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
  if (value.version !== BRIDGE_VERSION || typeof value.id !== "string" || value.id.length === 0) {
    return false;
  }
  if (value.ok === true) return isResult(value.result);
  if (value.ok === false) return isError(value.error);
  return false;
}

function isResult(value: unknown): boolean {
  if (!isRecord(value)) return false;
  if (!hasOnlyKeys(value, new Set(["kind", "revision", "snapshot"]))) return false;
  const kinds = new Set<unknown>([
    "ready",
    "changed",
    "saved",
    "stashed",
    "restored",
    "conflictResolved",
  ]);
  return kinds.has(value.kind)
    && (value.revision === undefined || Number.isSafeInteger(value.revision))
    && (value.snapshot === undefined || isSnapshot(value.snapshot, true));
}

function isError(value: unknown): boolean {
  if (!isRecord(value)) return false;
  if (!hasOnlyKeys(value, new Set(["code", "message", "recoverable", "latest"]))) return false;
  return typeof value.code === "string"
    && typeof value.message === "string"
    && typeof value.recoverable === "boolean"
    && (value.latest === undefined || isSnapshot(value.latest, true));
}

function isSnapshot(value: unknown, includesRevision: boolean): boolean {
  if (!isRecord(value)) return false;
  const keys = new Set(["draftID", "title", "document"]);
  if (includesRevision) keys.add("revision");
  return hasOnlyKeys(value, keys)
    && typeof value.draftID === "string"
    && typeof value.title === "string"
    && (!includesRevision || Number.isSafeInteger(value.revision));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: Set<string>): boolean {
  const keys = Object.keys(value);
  return keys.length === expected.size && keys.every((key) => expected.has(key));
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: Set<string>): boolean {
  return Object.keys(value).every((key) => allowed.has(key));
}
