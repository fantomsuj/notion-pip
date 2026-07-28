import assert from "node:assert/strict";
import test from "node:test";
import type { Editor } from "@tiptap/core";

import { SlashMenuController } from "./slash-menu-controller.ts";
import { installTestDOM } from "../test-support/dom.ts";

function makeEditor(document: Document): {
  editor: Editor;
  calls: string[];
} {
  const calls: string[] = [];
  const editorElement = document.createElement("div");
  document.body.append(editorElement);
  const chain = new Proxy(
    {},
    {
      get: (_target, property) => (..._arguments: unknown[]) => {
        calls.push(String(property));
        return property === "run" ? true : chain;
      },
    },
  );
  const state = {
    selection: {
      empty: true,
      from: 10,
      $from: {
        parentOffset: 3,
        parent: {
          isTextblock: true,
          textBetween: () => "/he",
        },
      },
    },
  };
  return {
    editor: {
      isEditable: true,
      state,
      chain: () => chain,
      view: {
        dom: editorElement,
        coordsAtPos: () => ({ left: 40, right: 40, top: 20, bottom: 30 }),
      },
    } as unknown as Editor,
    calls,
  };
}

test("slash menu owns filtered options positioning and active descendant accessibility", () => {
  const window = installTestDOM();
  const menu = window.document.createElement("div");
  menu.hidden = true;
  const page = window.document.createElement("div");
  Object.defineProperty(page, "getBoundingClientRect", {
    value: () => ({ left: 10, top: 5, width: 300, height: 200 }),
  });
  window.document.body.append(page, menu);
  const { editor } = makeEditor(window.document as unknown as Document);
  const controller = new SlashMenuController(
    menu as unknown as HTMLElement,
    page as unknown as HTMLElement,
  );

  controller.refresh(editor, false);

  assert.equal(menu.hidden, false);
  assert.deepEqual(
    Array.from(menu.children, (element) => element.textContent),
    ["Heading 1", "Heading 2", "Heading 3", "To-do list"],
  );
  assert.equal(menu.style.left, "30px");
  assert.equal(menu.style.top, "31px");
  assert.equal(menu.getAttribute("aria-activedescendant"), "slash-option-heading1");
  assert.equal(editor.view.dom.getAttribute("aria-expanded"), "true");
  assert.equal(
    editor.view.dom.getAttribute("aria-activedescendant"),
    "slash-option-heading1",
  );
});

test("slash menu routes keyboard selection and clears its owned DOM state", () => {
  const window = installTestDOM();
  const menu = window.document.createElement("div");
  menu.hidden = true;
  const { editor, calls } = makeEditor(window.document as unknown as Document);
  const controller = new SlashMenuController(
    menu as unknown as HTMLElement,
    null,
  );
  controller.refresh(editor, false);

  const next = new window.KeyboardEvent("keydown", {
    cancelable: true,
    key: "ArrowDown",
  });
  assert.equal(controller.handleKeyDown(editor, next as unknown as KeyboardEvent), true);
  assert.equal(next.defaultPrevented, true);
  assert.equal(menu.getAttribute("aria-activedescendant"), "slash-option-heading2");

  const select = new window.KeyboardEvent("keydown", {
    cancelable: true,
    key: "Enter",
  });
  assert.equal(controller.handleKeyDown(editor, select as unknown as KeyboardEvent), true);
  assert.deepEqual(calls, ["focus", "deleteRange", "toggleHeading", "run"]);
  assert.equal(menu.hidden, true);
  assert.equal(menu.children.length, 0);
  assert.equal(menu.hasAttribute("aria-activedescendant"), false);
  assert.equal(editor.view.dom.getAttribute("aria-expanded"), "false");
});
