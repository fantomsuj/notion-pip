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

test("failed change retries the identical request then allows later edits", async () => {
  const requests: BridgeRequest[] = [];
  const failures: string[] = [];
  let revision = 1;
  let sequence = 0;
  const publisher = new DebouncedChangePublisher(
    1_000,
    async (request) => {
      requests.push(structuredClone(request));
      if (requests.length === 1) throw new Error("acknowledgement lost");
      if (request.type === "changed" && request.snapshot.title === "A") revision = 2;
    },
    () => `change-${++sequence}`,
    (error) => failures.push(error.message),
  );

  publisher.changed({ draftID: "draft-1", title: "A", document: null }, () => revision);
  await assert.rejects(publisher.flush(), /acknowledgement lost/);
  publisher.changed({ draftID: "draft-1", title: "B", document: null }, () => revision);
  await publisher.flush();

  assert.equal(requests.length, 3);
  assert.deepEqual(requests[1], requests[0]);
  assert.equal(requests[0]?.id, "change-1");
  assert.equal(requests[2]?.id, "change-2");
  if (requests[2]?.type === "changed") assert.equal(requests[2].expectedRevision, 2);
  assert.deepEqual(failures, ["acknowledgement lost"]);
});

test("timer delivery rejection is observed instead of becoming unhandled", async () => {
  const failures: string[] = [];
  const unhandled: unknown[] = [];
  const listener = (error: unknown) => unhandled.push(error);
  process.on("unhandledRejection", listener);
  try {
    const publisher = new DebouncedChangePublisher(
      1,
      async () => { throw new Error("offline"); },
      () => "change-timer",
      (error) => failures.push(error.message),
    );
    publisher.changed({ draftID: "draft-1", title: "A", document: null }, 1);
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.deepEqual(failures, ["offline"]);
    assert.deepEqual(unhandled, []);
  } finally {
    process.off("unhandledRejection", listener);
  }
});

test("bridge client times out a missing native acknowledgement", async () => {
  const client = new BridgeClient(
    async () => new Promise<unknown>(() => {}),
    () => "timeout-1",
    5,
  );

  await assert.rejects(client.request("ready", {}), /timed out/);
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

test("reply guard enforces kind-specific result and snapshot contracts", () => {
  const snapshot = {
    draftID: "draft-1",
    title: "Note",
    document: { type: "doc", content: [{ type: "paragraph" }] },
    revision: 2,
  };
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "ready", revision: 2, snapshot } }), true);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "ready", revision: 2 } }), false);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "changed", revision: -1 } }), false);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "saved", revision: 2, snapshot } }), false);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "conflictResolved" } }), true);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "conflictResolved", snapshot } }), false);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "conflictResolved", revision: 2, snapshot } }), true);
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "unknown", revision: 2 } }), false);
});

test("reply guard rejects incomplete documents unknown errors and invalid identifiers", () => {
  const invalidSnapshot = {
    draftID: "",
    title: "Note",
    document: { type: "doc" },
    revision: 1,
  };
  assert.equal(isBridgeReply({ version: 1, id: "r", ok: true, result: { kind: "ready", revision: 1, snapshot: invalidSnapshot } }), false);
  assert.equal(isBridgeReply({
    version: 1,
    id: "r",
    ok: true,
    result: {
      kind: "ready",
      revision: 1,
      snapshot: {
        draftID: "draft-1",
        title: "Note",
        document: { type: "doc", content: [], credential: "nope" },
        revision: 1,
      },
    },
  }), false);
  assert.equal(isBridgeReply({
    version: 1,
    id: "r",
    ok: false,
    error: { code: "madeUp", message: "No", recoverable: false },
  }), false);
  assert.equal(isBridgeReply({
    version: 1,
    id: "r",
    ok: false,
    error: { code: "draftNotFound", message: "Missing", recoverable: true, extra: true },
  }), false);
  assert.equal(isBridgeReply({
    version: 1,
    id: "r",
    ok: false,
    error: {
      code: "draftNotFound",
      message: "Missing",
      recoverable: true,
      latest: {
        draftID: "draft-1",
        title: "Note",
        document: { type: "doc", content: [] },
        revision: 1,
      },
    },
  }), false);
});
