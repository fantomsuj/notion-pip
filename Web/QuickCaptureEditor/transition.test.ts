import assert from "node:assert/strict";
import test from "node:test";

import {
  DebouncedChangePublisher,
  requireAutosaveAcknowledgement,
} from "./bridge/debounced-change-publisher.ts";
import { canInstallSnapshot, normalizeDocument } from "./editor-state.ts";
import {
  EditorTransitionGate,
  conflictTransitionOperation,
} from "./state/editor-transition-gate.ts";
import { makeRequest, type BridgeRequest } from "./protocol.ts";

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
