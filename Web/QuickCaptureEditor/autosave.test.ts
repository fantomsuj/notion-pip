import assert from "node:assert/strict";
import test from "node:test";

import { BridgeClient } from "./bridge/bridge-client.ts";
import {
  DebouncedChangePublisher,
  requireAutosaveAcknowledgement,
  runAfterPendingChange,
} from "./bridge/debounced-change-publisher.ts";
import { normalizeDocument } from "./editor-state.ts";
import { BRIDGE_VERSION, type BridgeRequest } from "./protocol.ts";

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

test("new note waits for the pending changed acknowledgement before stashing", async () => {
  const order: string[] = [];
  let acknowledgeChange: (() => void) | undefined;
  const publisher = new DebouncedChangePublisher(1_000, async () => {
    order.push("changed");
    await new Promise<void>((resolve) => { acknowledgeChange = resolve; });
    order.push("acknowledged");
  }, () => "change-1");
  publisher.changed({ draftID: "draft-1", title: "Note", document: null }, 1);

  const newNote = runAfterPendingChange(publisher, async () => { order.push("stash"); });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(order, ["changed"]);
  acknowledgeChange?.();
  await newNote;

  assert.deepEqual(order, ["changed", "acknowledged", "stash"]);
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

test("newer pending work survives repeated failure of the earlier exact request", async () => {
  const requests: BridgeRequest[] = [];
  let attempt = 0;
  let sequence = 0;
  let revision = 1;
  const publisher = new DebouncedChangePublisher(
    1_000,
    async (request) => {
      requests.push(structuredClone(request));
      attempt += 1;
      if (attempt <= 2) throw new Error(`offline-${attempt}`);
      if (request.type === "changed") revision += 1;
    },
    () => `change-${++sequence}`,
  );

  publisher.changed({ draftID: "draft-1", title: "A", document: null }, () => revision);
  await assert.rejects(publisher.flush(), /offline-1/);
  publisher.changed({ draftID: "draft-1", title: "B", document: null }, () => revision);
  await assert.rejects(publisher.flush(), /offline-2/);
  await publisher.flush();

  assert.equal(requests.length, 4);
  assert.deepEqual(requests[1], requests[0]);
  assert.deepEqual(requests[2], requests[0]);
  assert.equal(requests[3]?.type, "changed");
  if (requests[3]?.type === "changed") {
    assert.equal(requests[3].id, "change-2");
    assert.equal(requests[3].snapshot.title, "B");
    assert.equal(requests[3].expectedRevision, 2);
  }
});

test("rapid save and stash actions serialize through their acknowledgements", async () => {
  const publisher = new DebouncedChangePublisher(1_000, async () => {});
  let active = 0;
  let maximumActive = 0;
  let finishSave: (() => void) | undefined;
  const order: string[] = [];

  const save = runAfterPendingChange(publisher, async () => {
    active += 1;
    maximumActive = Math.max(maximumActive, active);
    order.push("save-start");
    await new Promise<void>((resolve) => { finishSave = resolve; });
    order.push("save-end");
    active -= 1;
  });
  const stash = runAfterPendingChange(publisher, async () => {
    active += 1;
    maximumActive = Math.max(maximumActive, active);
    order.push("stash");
    active -= 1;
  });
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.deepEqual(order, ["save-start"]);
  finishSave?.();
  await Promise.all([save, stash]);
  assert.equal(maximumActive, 1);
  assert.deepEqual(order, ["save-start", "save-end", "stash"]);
});

test("recoverable persistence negative acknowledgement retains the exact autosave request", async () => {
  const requests: BridgeRequest[] = [];
  let attempt = 0;
  const publisher = new DebouncedChangePublisher(
    1_000,
    async (request) => {
      requests.push(structuredClone(request));
      attempt += 1;
      requireAutosaveAcknowledgement(attempt === 1
        ? {
            version: 1,
            id: request.id,
            ok: false,
            error: {
              code: "persistenceFailure",
              message: "Disk unavailable",
              recoverable: true,
            },
          }
        : {
            version: 1,
            id: request.id,
            ok: true,
            result: { kind: "changed", revision: 2 },
          });
    },
    () => "negative-ack-change",
  );

  publisher.changed({ draftID: "draft-1", title: "Unsaved", document: null }, 1);
  await assert.rejects(publisher.flush(), /Disk unavailable/);
  await publisher.flush();

  assert.equal(requests.length, 2);
  assert.deepEqual(requests[1], requests[0]);
});

test("failed autosave publishes retry availability and retries only the exact retained request", async () => {
  const requests: BridgeRequest[] = [];
  const availability: boolean[] = [];
  let attempt = 0;
  const publisher = new DebouncedChangePublisher(
    1_000,
    async (request) => {
      requests.push(structuredClone(request));
      attempt += 1;
      if (attempt === 1) throw new Error("Disk unavailable");
    },
    () => `autosave-${attempt + 1}`,
    () => {},
    (available) => availability.push(available),
  );

  publisher.changed({ draftID: "draft-1", title: "Exact edit", document: null }, 4);
  await assert.rejects(publisher.flush(), /Disk unavailable/);
  assert.equal(publisher.hasFailedRequest, true);
  assert.deepEqual(availability, [true]);

  await publisher.retryFailed();

  assert.equal(publisher.hasFailedRequest, false);
  assert.deepEqual(availability, [true, false]);
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[1], requests[0]);
  assert.equal(requests[1]?.id, "autosave-1");
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
