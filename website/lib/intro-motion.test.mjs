import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const css = readFileSync(join(root, "app/globals.css"), "utf8");
const motion = readFileSync(join(root, "lib/intro-motion.ts"), "utf8");

function cssVar(name) {
  const match = css.match(new RegExp(`${name}:\\s*([\\d.]+)s`));
  assert.ok(match, `expected ${name} in globals.css`);
  return Number(match[1]);
}

function tsMs(name) {
  const match = motion.match(new RegExp(`${name}\\s*[=:]\\s*(\\d+)`));
  assert.ok(match, `expected ${name} in intro-motion.ts`);
  return Number(match[1]);
}

describe("landing intro motion", () => {
  test("logo fades in, holds, and fades out", () => {
    assert.match(css, /@keyframes page-loader-mark/);
    assert.match(css, /page-loader-mark[\s\S]*page-loader-mark/);
    assert.equal(css.includes("page-loader-mark-cycle"), true);
    assert.ok(cssVar("--intro-logo-in") > 0);
    assert.ok(cssVar("--intro-logo-hold") > 0);
    assert.ok(cssVar("--intro-logo-out") > 0);
  });

  test("intro is slightly longer than the previous 1.2s splash", () => {
    const originalDoneMs = tsMs("originalIntroDoneMs");
    const computed =
      tsMs("logoInMs") +
      tsMs("logoHoldMs") +
      tsMs("logoOutMs") +
      tsMs("overlayExitMs");
    assert.equal(originalDoneMs, 1200);
    assert.equal(computed, 1850);
    assert.ok(computed > originalDoneMs);
    assert.equal(cssVar("--intro-logo-total") * 1000, 1450);
  });

  test("page info fades in as the logo fades out", () => {
    assert.match(css, /@keyframes page-stage-enter/);
    const contentDelay = cssVar("--intro-content-delay");
    const logoIn = cssVar("--intro-logo-in");
    const logoHold = cssVar("--intro-logo-hold");
    assert.equal(contentDelay, logoIn + logoHold);
    assert.ok(cssVar("--intro-content-fade") > 0.4);
  });

  test("CSS seconds stay in lockstep with TypeScript milliseconds", () => {
    assert.equal(cssVar("--intro-logo-in") * 1000, tsMs("logoInMs"));
    assert.equal(cssVar("--intro-logo-hold") * 1000, tsMs("logoHoldMs"));
    assert.equal(cssVar("--intro-logo-out") * 1000, tsMs("logoOutMs"));
    assert.equal(cssVar("--intro-overlay-exit") * 1000, tsMs("overlayExitMs"));
    assert.equal(cssVar("--intro-content-fade") * 1000, tsMs("contentFadeMs"));
  });
});
