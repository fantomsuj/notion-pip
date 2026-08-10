# Modularity roadmap

> Historical note: the capture editor and delivery pipeline described below
> were removed from the current architecture. This document records the
> earlier modularity work; it is not a map of the current implementation.

This document records the incremental implementation path following the
modularity audit. The changes are intentionally staged so behavior, signing,
and the single-product Swift package remain stable while boundaries become
compiler-visible.

## Phase 1: capability-oriented persistence

The first phase introduces narrow persistence ports for capture finalization,
delivery state transitions, delivery scheduling, and delivery journaling.
Services depend on only the operations they use; `CaptureRepository` remains
the production adapter. This makes policy actors independently substitutable
without prematurely splitting the SwiftData model layer.

Page restoration now consumes `PageWorkingSetPersisting` directly. This removes
the conditional protocol cast and legacy fallback from `AppRuntime`, making the
working-set contract explicit at composition time.

## Next phases

1. Move editor session state transitions out of the WebKit host, keeping WebKit
   as an adapter for rendering, focus, and bridge transport.
2. Generate or validate the Swift and TypeScript bridge message definitions
   from one versioned contract.
3. Split application composition, capture delivery, and page persistence into
   SwiftPM targets after their dependency directions no longer require source-
   level exceptions.
4. Continue decomposing session and runtime orchestration behind feature-owned
   facades, measuring target imports and concrete cross-layer dependencies in
   CI.

These steps should remain separate reviewable changes. In particular, target
splitting should follow—not precede—the capability and state-machine seams so
it enforces useful boundaries rather than reproducing current coupling across
more modules.
