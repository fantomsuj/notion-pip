import type { EditorSnapshot, JSONValue } from "./protocol.ts";

export function displayTitle(title: string): string {
  return title.trim().length === 0 ? "Untitled" : title;
}

interface CompositionKeyInput {
  readonly isComposing?: boolean;
  readonly keyCode?: number;
}

function isCompositionKey(input: CompositionKeyInput): boolean {
  return input.isComposing === true || input.keyCode === 229;
}

export type TitleRoute = "focusBody" | "none";

export interface TitleKeyInput extends CompositionKeyInput {
  readonly key: string;
  readonly atBoundary: boolean;
  readonly shiftKey?: boolean;
}

export function routeTitleKey(input: TitleKeyInput): TitleRoute {
  if (isCompositionKey(input)) return "none";
  if (input.key === "Enter" || (input.key === "Tab" && input.shiftKey !== true)) {
    return "focusBody";
  }
  if (input.key === "ArrowDown" && input.atBoundary) return "focusBody";
  return "none";
}

export function normalizeDocument(value: unknown): JSONValue {
  if (!isRecord(value) || value.type !== "doc" || !Array.isArray(value.content) || value.content.length === 0) {
    return { type: "doc", content: [{ type: "paragraph" }] };
  }
  return canonicalize(value) as JSONValue;
}

export function canInstallSnapshot(current: EditorSnapshot, next: EditorSnapshot): boolean {
  if (current.draftID !== next.draftID) return true;
  const currentRevision = current.revision ?? 0;
  const nextRevision = next.revision ?? 0;
  return nextRevision >= currentRevision;
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
