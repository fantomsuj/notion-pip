import assert from "node:assert/strict";
import test from "node:test";

import {
  BridgeClient,
  DebouncedChangePublisher,
  executeToolbarCommand,
  normalizeDocument,
  runAfterPendingChange,
  type EditorCommandTarget,
} from "./editor.ts";
import {
  BRIDGE_VERSION,
  isBridgeReply,
  makeRequest,
  type BridgeRequest,
} from "./protocol.ts";

test("editor normalization returns a canonical empty ProseMirror document", () => {
  assert.deepEqual(normalizeDocument(null), {
    type: "doc",
    content: [{ type: "paragraph" }],
  });
});

test("editor normalization recursively orders attributes and removes undefined values", () => {
  assert.deepEqual(
    normalizeDocument({
      content: [{ attrs: { z: 2, ignored: undefined, a: 1 }, type: "paragraph" }],
      type: "doc",
    }),
    {
      type: "doc",
      content: [{ type: "paragraph", attrs: { a: 1, z: 2 } }],
    },
  );
});

test("toolbar commands use the focused Tiptap chain and reject unknown commands", () => {
  const calls: string[] = [];
  const chain = new Proxy(
    {},
    {
      get: (_target, property) => () => {
        calls.push(String(property));
        return property === "run" ? true : chain;
      },
    },
  ) as EditorCommandTarget;

  assert.equal(executeToolbarCommand({ chain: () => chain }, "bold"), true);
  assert.deepEqual(calls, ["focus", "toggleBold", "run"]);
  assert.equal(executeToolbarCommand({ chain: () => chain }, "script"), false);
});

test("changed messages debounce to the latest canonical snapshot and expected revision", async () => {
  const requests: BridgeRequest[] = [];
  let sequence = 0;
  const publisher = new DebouncedChangePublisher(
    5,
    (request) => { requests.push(request); },
    () => `request-${++sequence}`,
  );

  publisher.changed({ draftID: "draft-1", title: "First", document: null }, 3);
  publisher.changed(
    {
      draftID: "draft-1",
      title: "Latest",
      document: { type: "doc", content: [{ type: "paragraph" }] },
    },
    3,
  );
  await new Promise((resolve) => setTimeout(resolve, 20));

  assert.equal(requests.length, 1);
  assert.deepEqual(requests[0], {
    version: BRIDGE_VERSION,
    id: "request-1",
    type: "changed",
    snapshot: {
      draftID: "draft-1",
      title: "Latest",
      document: { type: "doc", content: [{ type: "paragraph" }] },
    },
    expectedRevision: 3,
  });
});

test("bridge client requires the reply correlation ID to match", async () => {
  const sent: BridgeRequest[] = [];
  const client = new BridgeClient(async (request) => {
    sent.push(request);
    return { version: 1, id: request.id, ok: true, result: { kind: "saved", revision: 4 } };
  }, () => "save-7");

  const savePayload = {
    snapshot: { draftID: "draft-1", title: "Note", document: normalizeDocument(null) },
    expectedRevision: 4,
  };
  assert.deepEqual(await client.request("save", savePayload), {
    version: 1,
    id: "save-7",
    ok: true,
    result: { kind: "saved", revision: 4 },
  });
  assert.equal(sent[0]?.id, "save-7");

  const mismatched = new BridgeClient(async () => ({
    version: 1,
    id: "other",
    ok: true,
    result: { kind: "saved", revision: 4 },
  }), () => "save-8");
  await assert.rejects(mismatched.request("save", savePayload), /correlation/);
});

test("save and stash wait for the pending changed acknowledgement", async () => {
  const order: string[] = [];
  let acknowledgeChange: (() => void) | undefined;
  const publisher = new DebouncedChangePublisher(1_000, async () => {
    order.push("changed");
    await new Promise<void>((resolve) => { acknowledgeChange = resolve; });
    order.push("acknowledged");
  }, () => "change-1");
  publisher.changed({ draftID: "draft-1", title: "Note", document: null }, 1);

  const save = runAfterPendingChange(publisher, async () => { order.push("save"); });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(order, ["changed"]);
  acknowledgeChange?.();
  await save;

  assert.deepEqual(order, ["changed", "acknowledged", "save"]);
});

test("overlapping changes serialize and resolve revision after the prior acknowledgement", async () => {
  const requests: BridgeRequest[] = [];
  let revision = 1;
  let acknowledgeFirst: (() => void) | undefined;
  const publisher = new DebouncedChangePublisher(1_000, async (request) => {
    requests.push(request);
    if (requests.length === 1) {
      await new Promise<void>((resolve) => { acknowledgeFirst = resolve; });
      revision = 2;
    }
  }, () => `change-${requests.length + 1}`);

  publisher.changed({ draftID: "draft-1", title: "A", document: null }, () => revision);
  const first = publisher.flush();
  await new Promise((resolve) => setTimeout(resolve, 0));
  publisher.changed({ draftID: "draft-1", title: "B", document: null }, () => revision);
  const second = publisher.flush();

  assert.equal(requests.length, 1);
  acknowledgeFirst?.();
  await Promise.all([first, second]);
  assert.equal(requests.length, 2);
  assert.equal(requests[1]?.type, "changed");
  if (requests[1]?.type === "changed") assert.equal(requests[1].expectedRevision, 2);
});

test("protocol creates only allowlisted versioned request shapes", () => {
  assert.deepEqual(makeRequest("ready", "ready-1", {}), {
    version: 1,
    id: "ready-1",
    type: "ready",
  });
  assert.throws(() => makeRequest("eval" as "ready", "bad", {}), /Unsupported bridge request/);
});

test("reply guard rejects malformed, unknown-field, and unversioned replies", () => {
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: false, error: { code: "staleRevision", message: "Conflict", recoverable: true } }), true);
  assert.equal(isBridgeReply({ version: 2, id: "r", ok: true, result: { kind: "ready" } }), false);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "ready" }, token: "secret" }), false);
});
