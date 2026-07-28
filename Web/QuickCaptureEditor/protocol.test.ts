import assert from "node:assert/strict";
import test from "node:test";

import { isBridgeReply, makeRequest } from "./protocol.ts";

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
