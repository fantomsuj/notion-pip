import assert from "node:assert/strict";
import test from "node:test";

import { BRIDGE_VERSION, type BridgeRequest } from "./protocol.ts";
import { installTestDOM } from "./test-support/dom.ts";

test("quick capture controller installs the native surface and applies ready state", async () => {
  const testWindow = installTestDOM();
  testWindow.document.body.innerHTML = `
    <main id="page">
      <input id="title">
      <div id="editor"></div>
      <div id="status"></div>
      <div id="slash-menu" hidden></div>
      <div id="format-toolbar" hidden>
        <button data-format="bold"></button>
      </div>
      <button id="new-note"></button>
      <button id="retry" hidden></button>
    </main>
  `;
  const requests: BridgeRequest[] = [];
  const bridge = {
    postMessage: async (request: BridgeRequest) => {
      requests.push(request);
      return {
        version: BRIDGE_VERSION,
        id: request.id,
        ok: true as const,
        result: {
          kind: "ready" as const,
          revision: 3,
          snapshot: {
            draftID: "draft-1",
            title: "Ready title",
            revision: 3,
            document: {
              type: "doc",
              content: [{
                type: "paragraph",
                content: [{ type: "text", text: "Ready body" }],
              }],
            },
          },
        },
      };
    },
  };
  const { QuickCaptureEditorController } = await import(
    "./quick-capture-editor-controller.ts"
  );
  const title = testWindow.document.querySelector("#title") as unknown as HTMLInputElement | null;
  const status = testWindow.document.querySelector("#status") as unknown as HTMLElement | null;
  const editor = testWindow.document.querySelector("#editor") as unknown as HTMLElement | null;
  const slashMenu = testWindow.document.querySelector("#slash-menu") as unknown as HTMLElement | null;
  const formatToolbar = testWindow.document.querySelector("#format-toolbar") as unknown as HTMLElement | null;
  assert.ok(title && status && editor && slashMenu && formatToolbar);
  const controller = new QuickCaptureEditorController(bridge, {
    editor,
    title,
    status,
    slashMenu,
    formatToolbar,
    page: testWindow.document.querySelector("#page") as unknown as HTMLElement | null,
    newNoteButton: testWindow.document.querySelector("#new-note") as unknown as HTMLButtonElement | null,
    retryButton: testWindow.document.querySelector("#retry") as unknown as HTMLButtonElement | null,
  });

  controller.start();
  for (let attempt = 0; attempt < 20 && title.value !== "Ready title"; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1));
  }

  assert.equal(requests.length, 1);
  assert.equal(requests[0]?.type, "ready");
  assert.equal(title.value, "Ready title");
  assert.equal(title.disabled, false);
  assert.equal(status.dataset.state, "saved");
  assert.equal(status.textContent, "Saved");

  const browserWindow = testWindow as unknown as Window;
  const surface = browserWindow.NotionPiPBridge;
  assert.ok(surface);
  assert.deepEqual(surface.snapshot(), {
    draftID: "draft-1",
    title: "Ready title",
    revision: 3,
    document: {
      type: "doc",
      content: [{
        type: "paragraph",
        content: [{ type: "text", text: "Ready body" }],
      }],
    },
  });
});
