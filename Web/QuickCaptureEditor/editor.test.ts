import assert from "node:assert/strict";
import test from "node:test";

import {
  BLOCK_COMMANDS,
  BridgeClient,
  DebouncedChangePublisher,
  EditorTransitionGate,
  canInstallSnapshot,
  conflictTransitionOperation,
  displayTitle,
  executeToolbarCommand,
  filterBlockCommands,
  normalizeDocument,
  requireAutosaveAcknowledgement,
  routeOverlayKey,
  routeTitleKey,
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

test("display titles fall back without changing non-empty title text", () => {
  assert.equal(displayTitle(""), "Untitled");
  assert.equal(displayTitle("  \n"), "Untitled");
  assert.equal(displayTitle("  Project notes  "), "  Project notes  ");
});

test("title keys route focus into the body at the intended boundaries", () => {
  assert.equal(routeTitleKey({ key: "Enter", atBoundary: false }), "focusBody");
  assert.equal(routeTitleKey({ key: "Tab", atBoundary: false }), "focusBody");
  assert.equal(routeTitleKey({ key: "ArrowDown", atBoundary: true }), "focusBody");
  assert.equal(routeTitleKey({ key: "ArrowDown", atBoundary: false }), "none");
  assert.equal(routeTitleKey({ key: "ArrowUp", atBoundary: true }), "none");
});

test("overlay keys route only while the slash menu is open", () => {
  assert.equal(routeOverlayKey({ key: "ArrowUp", isOpen: true }), "previous");
  assert.equal(routeOverlayKey({ key: "ArrowDown", isOpen: true }), "next");
  assert.equal(routeOverlayKey({ key: "Enter", isOpen: true }), "select");
  assert.equal(routeOverlayKey({ key: "Escape", isOpen: true }), "dismiss");
  assert.equal(routeOverlayKey({ key: "Escape", isOpen: false }), "none");
  assert.equal(routeOverlayKey({ key: "Tab", isOpen: true }), "none");
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

test("transition gate starts locked and unlocks only after ready is applied", async () => {
  const locks: boolean[] = [];
  let acknowledge: ((value: unknown) => void) | undefined;
  const publisher = new DebouncedChangePublisher(1_000, async () => {});
  const gate = new EditorTransitionGate(
    publisher,
    async () => new Promise((resolve) => { acknowledge = resolve; }),
    () => true,
    (locked) => locks.push(locked),
  );

  const ready = gate.perform({
    key: "ready",
    drainPendingChanges: false,
    expectedKind: "ready",
    makeRequest: () => makeRequest("ready", "ready-transition", {}),
  });
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.equal(gate.isLocked, true);
  assert.deepEqual(locks, [true]);
  acknowledge?.({
    version: 1,
    id: "ready-transition",
    ok: true,
    result: {
      kind: "ready",
      revision: 1,
      snapshot: {
        draftID: "draft-1",
        title: "Ready",
        document: normalizeDocument(null),
        revision: 1,
      },
    },
  });
  await ready;

  assert.equal(gate.isLocked, false);
  assert.deepEqual(locks, [true, false]);
});

test("negative ready remains locked and retries the exact request", async () => {
  const requests: BridgeRequest[] = [];
  let retryAvailable = false;
  const publisher = new DebouncedChangePublisher(1_000, async () => {});
  const gate = new EditorTransitionGate(
    publisher,
    async (request) => {
      requests.push(structuredClone(request));
      if (requests.length === 1) {
        return {
          version: 1,
          id: request.id,
          ok: false,
          error: {
            code: "draftNotFound",
            message: "Draft unavailable",
            recoverable: true,
          },
        };
      }
      return {
        version: 1,
        id: request.id,
        ok: true,
        result: {
          kind: "ready",
          revision: 1,
          snapshot: {
            draftID: "draft-1",
            title: "Recovered",
            document: normalizeDocument(null),
            revision: 1,
          },
        },
      };
    },
    () => true,
    () => {},
    (available) => { retryAvailable = available; },
  );
  const operation = {
    key: "ready",
    expectedKind: "ready" as const,
    drainPendingChanges: false,
    unlockOnDefinitiveRejection: false,
    makeRequest: () => makeRequest("ready", "ready-negative", {}),
  };

  await assert.rejects(gate.perform(operation), /Draft unavailable/);
  assert.equal(gate.isLocked, true);
  assert.equal(retryAvailable, true);
  await gate.retryPending();

  assert.equal(gate.isLocked, false);
  assert.equal(retryAvailable, false);
  assert.deepEqual(requests[1], requests[0]);
});

test("stash transition locks before draining and captures only after the old draft acknowledgement", async () => {
  const order: string[] = [];
  let acknowledgeChange: (() => void) | undefined;
  let locked = false;
  const publisher = new DebouncedChangePublisher(1_000, async () => {
    order.push("changed");
    await new Promise<void>((resolve) => { acknowledgeChange = resolve; });
    order.push("changed-acknowledged");
  }, () => "old-draft-change");
  publisher.changed({ draftID: "draft-1", title: "Old edit", document: null }, 1);
  const gate = new EditorTransitionGate(
    publisher,
    async (request) => {
      order.push(`dispatch-${request.type}`);
      return {
        version: 1,
        id: request.id,
        ok: true,
        result: {
          kind: "stashed",
          revision: 1,
          snapshot: {
            draftID: "draft-2",
            title: "",
            document: normalizeDocument(null),
            revision: 1,
          },
        },
      };
    },
    () => true,
    (value) => { locked = value; },
  );

  const stash = gate.perform({
    key: "stash",
    expectedKind: "stashed",
    makeRequest: () => {
      order.push("capture-stash");
      return makeRequest("stash", "stash-transition", {
        snapshot: { draftID: "draft-1", title: "Old edit", document: normalizeDocument(null) },
        expectedRevision: 2,
      });
    },
  });
  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.equal(locked, true);
  assert.deepEqual(order, ["changed"]);
  acknowledgeChange?.();
  await stash;

  assert.equal(locked, false);
  assert.deepEqual(order, ["changed", "changed-acknowledged", "capture-stash", "dispatch-stash"]);
});

test("definitive old-draft autosave rejection cancels the transition without retaining a retry", async () => {
  let transitionCaptured = false;
  let locked = false;
  let retryAvailable = false;
  const publisher = new DebouncedChangePublisher(
    1_000,
    async (request) => {
      requireAutosaveAcknowledgement({
        version: 1,
        id: request.id,
        ok: false,
        error: {
          code: "staleRevision",
          message: "A newer draft revision is available.",
          recoverable: true,
          latest: {
            draftID: "draft-1",
            title: "Latest",
            document: normalizeDocument(null),
            revision: 2,
          },
        },
      });
    },
    () => "stale-old-draft-change",
  );
  publisher.changed({ draftID: "draft-1", title: "Current work", document: null }, 1);
  const gate = new EditorTransitionGate(
    publisher,
    async () => { throw new Error("transition must not dispatch"); },
    () => true,
    (value) => { locked = value; },
    (available) => { retryAvailable = available; },
  );

  await assert.rejects(gate.perform({
    key: "restore:other:1",
    expectedKind: "restored",
    makeRequest: () => {
      transitionCaptured = true;
      return makeRequest("restore", "restore-after-stale", {
        draftID: "other",
        expectedRevision: 1,
      });
    },
  }), /newer draft revision/);

  assert.equal(transitionCaptured, false);
  assert.equal(locked, false);
  assert.equal(retryAvailable, false);
  await publisher.flush();
});

test("missing old draft keeps the transition locked with the exact autosave retry", async () => {
  let locked = false;
  let retryAvailable = false;
  let transitionCaptured = false;
  const publisher = new DebouncedChangePublisher(
    1_000,
    async (request) => {
      requireAutosaveAcknowledgement({
        version: 1,
        id: request.id,
        ok: false,
        error: {
          code: "draftNotFound",
          message: "This draft is no longer available.",
          recoverable: true,
        },
      });
    },
    () => "missing-old-draft-change",
  );
  publisher.changed({ draftID: "draft-1", title: "Visible work", document: null }, 1);
  const gate = new EditorTransitionGate(
    publisher,
    async () => { throw new Error("transition must not dispatch"); },
    () => true,
    (value) => { locked = value; },
    (available) => { retryAvailable = available; },
  );

  await assert.rejects(gate.perform({
    key: "stash:missing-draft",
    expectedKind: "stashed",
    makeRequest: () => {
      transitionCaptured = true;
      return makeRequest("stash", "stash-missing-draft", {
        snapshot: {
          draftID: "draft-1",
          title: "Visible work",
          document: normalizeDocument(null),
        },
        expectedRevision: 1,
      });
    },
  }), /no longer available/);

  assert.equal(transitionCaptured, false);
  assert.equal(locked, true);
  assert.equal(retryAvailable, true);
  assert.equal(gate.hasPendingTransition, true);
});

test("conflict capture discards the superseded queued autosave", async () => {
  const changedRequests: BridgeRequest[] = [];
  const transitionRequests: BridgeRequest[] = [];
  const publisher = new DebouncedChangePublisher(
    5,
    async (request) => { changedRequests.push(request); },
    () => "superseded-change",
  );
  publisher.changed({ draftID: "draft-1", title: "Discard me", document: null }, 1);
  const gate = new EditorTransitionGate(
    publisher,
    async (request) => {
      transitionRequests.push(request);
      return {
        version: 1,
        id: request.id,
        ok: true,
        result: {
          kind: "conflictResolved",
          revision: 2,
          snapshot: {
            draftID: "draft-1",
            title: "Native latest",
            document: normalizeDocument(null),
            revision: 2,
          },
        },
      };
    },
    () => true,
    () => {},
  );

  await gate.perform(conflictTransitionOperation(
    "reloadLatest",
    "reload-latest",
    () => ({
      draftID: "draft-1",
      title: "Discard me",
      document: normalizeDocument(null),
    }),
  ));
  await new Promise((resolve) => setTimeout(resolve, 20));

  assert.equal(transitionRequests.length, 1);
  assert.equal(changedRequests.length, 0);
});

test("ambiguous conflict acknowledgement stays locked and retries the exact captured request", async () => {
  const requests: BridgeRequest[] = [];
  let locked = false;
  let capturedTitle = "Captured before timeout";
  const publisher = new DebouncedChangePublisher(1_000, async () => {});
  const gate = new EditorTransitionGate(
    publisher,
    async (request) => {
      requests.push(structuredClone(request));
      if (requests.length === 1) throw new Error("Native bridge acknowledgement timed out");
      return {
        version: 1,
        id: request.id,
        ok: true,
        result: {
          kind: "conflictResolved",
          revision: 1,
          snapshot: {
            draftID: "copy-1",
            title: "Captured before timeout",
            document: normalizeDocument(null),
            revision: 1,
          },
        },
      };
    },
    () => true,
    (value) => { locked = value; },
  );
  const operation = {
    key: "conflict-save-as-new",
    expectedKind: "conflictResolved" as const,
    makeRequest: () => makeRequest("resolveConflict", "conflict-operation", {
      action: "saveAsNew",
      snapshot: {
        draftID: "draft-1",
        title: capturedTitle,
        document: normalizeDocument(null),
      },
    }),
  };

  await assert.rejects(gate.perform(operation), /timed out/);
  assert.equal(locked, true);
  if (!locked) capturedTitle = "Must never be accepted";
  await gate.perform(operation);

  assert.equal(locked, false);
  assert.equal(requests.length, 2);
  assert.deepEqual(requests[1], requests[0]);
  if (requests[1]?.type === "resolveConflict") {
    assert.equal(requests[1].snapshot.title, "Captured before timeout");
  }
});

test("applied terminal conflict receipt replays without redispatch or reapply", async () => {
  const requests: BridgeRequest[] = [];
  let applyCount = 0;
  let capturedTitle = "Captured work";
  const publisher = new DebouncedChangePublisher(1_000, async () => {});
  const reply = {
    version: 1 as const,
    id: "terminal-conflict",
    ok: true as const,
    result: {
      kind: "conflictResolved" as const,
      revision: 1,
      snapshot: {
        draftID: "copy-1",
        title: "Captured work",
        document: normalizeDocument(null),
        revision: 1,
      },
    },
  };
  const gate = new EditorTransitionGate(
    publisher,
    async (request) => {
      requests.push(structuredClone(request));
      return reply;
    },
    () => { applyCount += 1; return true; },
    () => {},
  );
  const operation = () => ({
    key: "conflict:terminal-conflict:saveAsNew",
    expectedKind: "conflictResolved" as const,
    retainTerminalReceipt: true,
    makeRequest: () => makeRequest("resolveConflict", "terminal-conflict", {
      action: "saveAsNew",
      snapshot: {
        draftID: "draft-1",
        title: capturedTitle,
        document: normalizeDocument(null),
      },
    }),
  });

  const first = await gate.perform(operation());
  capturedTitle = "New editor state after applied success";
  const replay = await gate.perform(operation());

  assert.deepEqual(replay, first);
  assert.equal(requests.length, 1);
  assert.equal(applyCount, 1);

  await assert.rejects(gate.perform({
    key: "restore:ambiguous-draft:1",
    expectedKind: "restored",
    makeRequest: () => makeRequest("restore", "ambiguous-restore", {
      draftID: "ambiguous-draft",
      expectedRevision: 1,
    }),
  }), /Malformed bridge reply/);
  await assert.rejects(gate.perform(operation()), /pending transition/);
});

test("ambiguous transition rejects a different operation until the exact request succeeds", async () => {
  const publisher = new DebouncedChangePublisher(1_000, async () => {});
  const gate = new EditorTransitionGate(
    publisher,
    async () => { throw new Error("Malformed bridge reply"); },
    () => true,
    () => {},
  );
  await assert.rejects(gate.perform({
    key: "restore-draft-1",
    expectedKind: "restored",
    makeRequest: () => makeRequest("restore", "restore-1", { draftID: "draft-1", expectedRevision: 2 }),
  }), /Malformed/);

  await assert.rejects(gate.perform({
    key: "restore-draft-2",
    expectedKind: "restored",
    makeRequest: () => makeRequest("restore", "restore-2", { draftID: "draft-2", expectedRevision: 1 }),
  }), /pending transition/);
});

test("snapshot installation is monotonic within one draft and permits a draft switch", () => {
  const current = {
    draftID: "draft-1",
    title: "Current",
    document: normalizeDocument(null),
    revision: 5,
  };
  assert.equal(canInstallSnapshot(current, { ...current, title: "Older", revision: 4 }), false);
  assert.equal(canInstallSnapshot(current, { ...current, title: "Same", revision: 5 }), true);
  assert.equal(canInstallSnapshot(current, { ...current, title: "Newer", revision: 6 }), true);
  assert.equal(canInstallSnapshot(current, { ...current, draftID: "draft-2", revision: 1 }), true);
});

test("protocol creates only allowlisted versioned request shapes", () => {
  assert.deepEqual(makeRequest("ready", "ready-1", {}), {
    version: 1,
    id: "ready-1",
    type: "ready",
  });
  assert.deepEqual(
    makeRequest("ready", "ready-2", {
      version: 99,
      id: "attacker",
      type: "save",
      credential: "secret",
    } as never),
    { version: 1, id: "ready-2", type: "ready" },
  );
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
