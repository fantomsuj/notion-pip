/**
 * Landing intro timings.
 *
 * The previous splash faded the logo in over 250ms, then dismissed the
 * overlay at 800ms (JS fallback at 1200ms) with no independent logo fade-out
 * and no page-content entrance.
 */
export const originalIntroDoneMs = 1200;

export const introMotion = {
  logoInMs: 450,
  logoHoldMs: 500,
  logoOutMs: 500,
  overlayExitMs: 400,
  contentFadeMs: 750,
  wordmarkDelayMs: 80,
  trackDelayMs: 120,
} as const;

export const introLogoTotalMs =
  introMotion.logoInMs + introMotion.logoHoldMs + introMotion.logoOutMs;

export const introContentDelayMs =
  introMotion.logoInMs + introMotion.logoHoldMs;

export const introOverlayDelayMs = introLogoTotalMs;

export const introDoneMs = introLogoTotalMs + introMotion.overlayExitMs;
