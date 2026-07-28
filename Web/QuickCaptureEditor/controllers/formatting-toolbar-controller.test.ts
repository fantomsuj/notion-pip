import assert from "node:assert/strict";
import test from "node:test";
import type { Editor } from "@tiptap/core";

import { FormattingToolbarController } from "./formatting-toolbar-controller.ts";
import { installTestDOM } from "../test-support/dom.ts";

function makeEditor(document: Document): {
  editor: Editor;
  calls: string[];
} {
  const calls: string[] = [];
  const editorElement = document.createElement("div");
  editorElement.tabIndex = 0;
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
  const selection = { empty: false, from: 1, to: 4 };
  return {
    editor: {
      isEditable: true,
      isFocused: true,
      isActive: (mark: string) => mark === "bold",
      state: {
        selection,
        doc: { textBetween: () => "abc" },
      },
      chain: () => chain,
      commands: { focus: () => true },
      view: {
        dom: editorElement,
        state: { selection },
        coordsAtPos: (position: number) => position === 1
          ? { left: 80, right: 80, top: 60, bottom: 70 }
          : { left: 140, right: 140, top: 60, bottom: 70 },
        focus: () => editorElement.focus(),
      },
    } as unknown as Editor,
    calls,
  };
}

test("formatting toolbar owns active state positioning and mutation locking", () => {
  const window = installTestDOM();
  const page = window.document.createElement("div");
  const toolbar = window.document.createElement("div");
  toolbar.hidden = true;
  toolbar.innerHTML = `
    <button data-format="bold"></button>
    <button data-format="italic"></button>
  `;
  Object.defineProperties(toolbar, {
    offsetHeight: { value: 20 },
    offsetWidth: { value: 100 },
  });
  Object.defineProperty(page, "getBoundingClientRect", {
    value: () => ({ left: 10, top: 10, width: 300, height: 200 }),
  });
  window.document.body.append(page, toolbar);
  const { editor } = makeEditor(window.document as unknown as Document);
  const controller = new FormattingToolbarController(
    toolbar as unknown as HTMLElement,
    page as unknown as HTMLElement,
  );
  controller.bind(editor, () => false);

  controller.refresh(editor, false);

  const buttons = Array.from(toolbar.querySelectorAll("button"));
  assert.equal(toolbar.hidden, false);
  assert.equal(buttons[0]?.getAttribute("aria-pressed"), "true");
  assert.equal(buttons[1]?.getAttribute("aria-pressed"), "false");
  assert.equal(toolbar.style.left, "50px");
  assert.equal(toolbar.style.top, "22px");

  controller.setMutationLocked(true);
  assert.equal(toolbar.hidden, true);
  assert.equal(buttons.every((button) => button.disabled), true);
});

test("formatting toolbar owns keyboard entry traversal command routing and dismissal", () => {
  const window = installTestDOM();
  const toolbar = window.document.createElement("div");
  toolbar.hidden = false;
  toolbar.innerHTML = `
    <button data-format="bold"></button>
    <button data-format="italic"></button>
  `;
  window.document.body.append(toolbar);
  const { editor, calls } = makeEditor(window.document as unknown as Document);
  const controller = new FormattingToolbarController(
    toolbar as unknown as HTMLElement,
    null,
  );
  controller.bind(editor, () => false);

  const enterToolbar = new window.KeyboardEvent("keydown", {
    cancelable: true,
    key: "Tab",
  });
  assert.equal(
    controller.handleEditorKeyDown(editor, enterToolbar as unknown as KeyboardEvent),
    true,
  );
  const buttons = Array.from(toolbar.querySelectorAll("button"));
  assert.equal(window.document.activeElement, buttons[0]);

  buttons[0]?.click();
  assert.deepEqual(calls, ["focus", "toggleBold", "run"]);
  assert.equal(window.document.activeElement, buttons[0]);

  const next = new window.KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key: "Tab",
  });
  buttons[0]?.dispatchEvent(next);
  assert.equal(window.document.activeElement, buttons[1]);

  const dismiss = new window.KeyboardEvent("keydown", {
    cancelable: true,
    key: "Escape",
  });
  assert.equal(
    controller.handleEditorKeyDown(editor, dismiss as unknown as KeyboardEvent),
    true,
  );
  assert.equal(toolbar.hidden, true);
});
