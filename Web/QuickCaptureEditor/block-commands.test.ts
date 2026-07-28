import assert from "node:assert/strict";
import test from "node:test";

import {
  BLOCK_COMMANDS,
  executeBlockCommand,
  filterBlockCommands,
  routeOverlayKey,
  slashQueryAtSelection,
  type BlockCommandTarget,
} from "./block-commands.ts";
import { displayTitle, routeTitleKey } from "./editor-state.ts";

function slashState(text: string, empty = true) {
  const blockStart = 7;
  return {
    selection: {
      empty,
      from: blockStart + text.length,
      $from: {
        parentOffset: text.length,
        parent: {
          isTextblock: true,
          textBetween: (from: number, to: number) => text.slice(from, to),
        },
      },
    },
  };
}

test("block commands expose the supported blocks in stable menu order", () => {
  assert.deepEqual(BLOCK_COMMANDS.map((item) => item.id), [
    "text",
    "heading1",
    "heading2",
    "heading3",
    "bulletList",
    "orderedList",
    "taskList",
    "quote",
    "codeBlock",
    "divider",
  ]);
  assert.deepEqual(
    BLOCK_COMMANDS.map((item) => item.command),
    [
      "setParagraph",
      "toggleHeading",
      "toggleHeading",
      "toggleHeading",
      "toggleBulletList",
      "toggleOrderedList",
      "toggleTaskList",
      "toggleBlockquote",
      "toggleCodeBlock",
      "setHorizontalRule",
    ],
  );
});

test("block command filtering is case-insensitive and retains catalog order", () => {
  assert.deepEqual(
    filterBlockCommands("  HeAd  ").map((item) => item.id),
    ["heading1", "heading2", "heading3"],
  );
  assert.deepEqual(
    filterBlockCommands("list").map((item) => item.id),
    ["bulletList", "orderedList", "taskList"],
  );
  assert.deepEqual(
    filterBlockCommands("").map((item) => item.id),
    BLOCK_COMMANDS.map((item) => item.id),
  );
});

test("block command filtering matches aliases", () => {
  assert.deepEqual(filterBlockCommands("todo").map((item) => item.id), ["taskList"]);
  assert.deepEqual(filterBlockCommands("numbered").map((item) => item.id), ["orderedList"]);
  assert.deepEqual(filterBlockCommands("hr").map((item) => item.id), ["divider"]);
});

test("slash query detection recognizes an empty slash at the start of a text block", () => {
  assert.deepEqual(slashQueryAtSelection(slashState("/")), {
    from: 7,
    to: 8,
    query: "",
  });
});

test("slash query detection returns text used to filter the block catalog", () => {
  const match = slashQueryAtSelection(slashState("/hea"));

  assert.deepEqual(match, { from: 7, to: 11, query: "hea" });
  assert.deepEqual(
    filterBlockCommands(match?.query ?? "").map((item) => item.id),
    ["heading1", "heading2", "heading3"],
  );
});

test("slash query detection rejects non-leading slashes and expanded selections", () => {
  assert.equal(slashQueryAtSelection(slashState("notes /hea")), undefined);
  assert.equal(slashQueryAtSelection(slashState("/hea", false)), undefined);
});

test("block command dispatch deletes the slash query then runs the exact Tiptap command", () => {
  const cases = [
    ["text", "setParagraph", undefined],
    ["heading1", "toggleHeading", { level: 1 }],
    ["heading2", "toggleHeading", { level: 2 }],
    ["heading3", "toggleHeading", { level: 3 }],
    ["bulletList", "toggleBulletList", undefined],
    ["orderedList", "toggleOrderedList", undefined],
    ["taskList", "toggleTaskList", undefined],
    ["quote", "toggleBlockquote", undefined],
    ["codeBlock", "toggleCodeBlock", undefined],
    ["divider", "setHorizontalRule", undefined],
  ] as const;

  for (const [id, command, options] of cases) {
    const calls: Array<{ name: string; arguments: unknown[] }> = [];
    const chain = new Proxy(
      {},
      {
        get: (_target, property) => (...args: unknown[]) => {
          calls.push({ name: String(property), arguments: args });
          return property === "run" ? true : chain;
        },
      },
    ) as BlockCommandTarget;
    const editor = {
      state: slashState("/hea"),
      chain: () => chain,
    };

    assert.equal(executeBlockCommand(editor, id), true, id);
    assert.deepEqual(calls, [
      { name: "focus", arguments: [] },
      { name: "deleteRange", arguments: [{ from: 7, to: 11 }] },
      { name: command, arguments: options === undefined ? [] : [options] },
      { name: "run", arguments: [] },
    ], id);
  }
});

test("block command dispatch rejects unknown IDs without creating a command chain", () => {
  let chainCount = 0;
  const editor = {
    state: slashState("/unknown"),
    chain: () => {
      chainCount += 1;
      return {} as BlockCommandTarget;
    },
  };

  assert.equal(executeBlockCommand(editor, "database"), false);
  assert.equal(chainCount, 0);
});

test("display titles fall back without changing non-empty title text", () => {
  assert.equal(displayTitle(""), "Untitled");
  assert.equal(displayTitle("  \n"), "Untitled");
  assert.equal(displayTitle("  Project notes  "), "  Project notes  ");
});

test("title keys route focus into the body at the intended boundaries", () => {
  assert.equal(routeTitleKey({ key: "Enter", atBoundary: false }), "focusBody");
  assert.equal(routeTitleKey({ key: "Tab", atBoundary: false }), "focusBody");
  assert.equal(routeTitleKey({ key: "Tab", atBoundary: false, shiftKey: true }), "none");
  assert.equal(routeTitleKey({ key: "ArrowDown", atBoundary: true }), "focusBody");
  assert.equal(routeTitleKey({ key: "ArrowDown", atBoundary: false }), "none");
  assert.equal(routeTitleKey({ key: "ArrowUp", atBoundary: true }), "none");
  assert.equal(
    routeTitleKey({ key: "Enter", atBoundary: true, isComposing: true }),
    "none",
  );
  assert.equal(
    routeTitleKey({ key: "Enter", atBoundary: true, keyCode: 229 }),
    "none",
  );
});
test("overlay keys route only while the slash menu is open", () => {
  assert.equal(routeOverlayKey({ key: "ArrowUp", isOpen: true }), "previous");
  assert.equal(routeOverlayKey({ key: "ArrowDown", isOpen: true }), "next");
  assert.equal(routeOverlayKey({ key: "Enter", isOpen: true }), "select");
  assert.equal(routeOverlayKey({ key: "Escape", isOpen: true }), "dismiss");
  assert.equal(routeOverlayKey({ key: "Escape", isOpen: false }), "none");
  assert.equal(routeOverlayKey({ key: "Tab", isOpen: true }), "none");
  assert.equal(
    routeOverlayKey({ key: "Enter", isOpen: true, isComposing: true }),
    "none",
  );
  assert.equal(
    routeOverlayKey({ key: "Escape", isOpen: true, keyCode: 229 }),
    "none",
  );
});
