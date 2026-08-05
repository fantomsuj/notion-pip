import assert from "node:assert/strict";
import test from "node:test";

import {
  executeFormattingCommand,
  formattingState,
  isLinkPaste,
  type FormattingCommandTarget,
} from "./formatting.ts";
import { normalizeDocument } from "./editor-state.ts";

test("editor normalization returns a canonical empty ProseMirror document", () => {
  assert.deepEqual(normalizeDocument(null), {
    type: "doc",
    content: [{ type: "paragraph" }],
  });
});

test("valid editor documents pass through without a recursive canonicalization copy", () => {
  const document = {
    content: [{ attrs: { z: 2, a: 1 }, type: "paragraph" }],
    type: "doc",
  };

  assert.equal(normalizeDocument(document), document);
});

test("formatting state projects all supported active marks into a plain object", () => {
  const active = new Set(["bold", "underline", "code", "link"]);

  assert.deepEqual(formattingState({ isActive: (mark) => active.has(mark) }), {
    bold: true,
    italic: false,
    underline: true,
    strike: false,
    code: true,
    link: true,
  });
});

test("formatting commands dispatch each supported mark through a focused chain", () => {
  const cases = [
    ["bold", "toggleBold"],
    ["italic", "toggleItalic"],
    ["underline", "toggleUnderline"],
    ["strike", "toggleStrike"],
    ["code", "toggleCode"],
    ["link", "toggleLink"],
  ] as const;

  for (const [command, method] of cases) {
    const calls: Array<{ name: string; arguments: unknown[] }> = [];
    const chain = new Proxy(
      {},
      {
        get: (_target, property) => (...args: unknown[]) => {
          calls.push({ name: String(property), arguments: args });
          return property === "run" ? true : chain;
        },
      },
    ) as FormattingCommandTarget;

    assert.equal(executeFormattingCommand({ chain: () => chain }, command), true, command);
    assert.deepEqual(calls, [
      { name: "focus", arguments: [] },
      { name: method, arguments: [] },
      { name: "run", arguments: [] },
    ], command);
  }
});

test("link paste accepts only one HTTP or HTTPS URL over a non-empty selection", () => {
  const selected = { empty: false };

  assert.equal(isLinkPaste(selected, "https://example.com/path?q=1"), true);
  assert.equal(isLinkPaste(selected, " http://example.com/path "), true);
  assert.equal(isLinkPaste({ empty: true }, "https://example.com"), false);
  assert.equal(isLinkPaste(selected, "javascript:alert(1)"), false);
  assert.equal(isLinkPaste(selected, "data:text/html,unsafe"), false);
  assert.equal(isLinkPaste(selected, "https://one.example\nhttps://two.example"), false);
  assert.equal(isLinkPaste(selected, "not a URL"), false);
});
