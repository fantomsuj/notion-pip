# Shortcut Lifecycle Recovery Design

## Goal

Keep both the panel and Quick Capture global shortcuts usable after system wake, display wake, fast user switching, and session reactivation without polling. Preserve the user's last known-good configuration and the panel's menu-bar recovery path whenever Carbon cannot provide the panel shortcut.

## Current behavior

`AppRuntime` owns two independent `CarbonGlobalShortcutRegistrar` instances. Each registrar deliberately treats registration of its current chord as a handler-only update, so runtime cannot use the existing API to prove that a Carbon registration survived a lifecycle change. Panel registration failure is represented by `globalShortcutUnavailable` and forces the menu-bar icon visible; Quick Capture registration failure has no health state. Settings reject equal chords, but the two settings controls report registration failures independently.

## Architecture

Add a small `ShortcutLifecycleCoordinator` on the main actor. It observes only public `NSWorkspace` notifications for system wake, display wake, and session activation. A notification invalidates any pending recovery and schedules one coalesced callback. Recovery is event-driven: there is no timer that runs in the absence of a lifecycle event.

The coordinator owns scheduling and lifetime, not shortcut policy. An injected one-shot scheduler makes burst coalescing, teardown, and stale callback behavior deterministic in tests. Every scheduled callback carries a generation; settings changes and teardown advance the generation so old work cannot overwrite newer state.

Extend the registrar boundary with explicit forced revalidation. Revalidation unregisters and reinstalls the currently configured chord with its existing handler even when the value is unchanged. Carbon errors are classified as:

- `conflict` when `RegisterEventHotKey` returns `eventHotKeyExistsErr`;
- `transient` for other event-handler or hot-key failures.

The registrar still attempts to restore its previous known-good registration after a failed replacement.

## Runtime recovery

`AppRuntime.start()` performs normal initial registration, then starts lifecycle observation. A coalesced lifecycle event snapshots the current configuration generation and revalidates panel and Quick Capture independently. Successful results resolve that shortcut's health issue. A conflict records an unavailable issue immediately and does not retry. A transient failure records the issue and requests one bounded, coalesced follow-up attempt. This follow-up is part of the lifecycle event, not periodic polling.

Panel and Quick Capture receive distinct service-health issues. The effective menu-bar visibility remains derived only from panel availability: it is forced on from the first panel failure until panel registration succeeds. A Quick Capture-only failure never changes the user's menu-bar preference.

If settings change while recovery is pending or in its one-shot follow-up, runtime invalidates the old generation. The settings operation registers the requested chord before publishing or persisting it, then asks the lifecycle coordinator to discard stale work. Callback results from an older configuration are ignored.

## Atomic shortcut configuration

Treat the two shortcut values as one `ShortcutConfiguration` value inside runtime, while retaining `globalShortcut` and `quickCaptureShortcut` as read-only computed accessors for existing call sites. Every settings mutation validates the complete candidate pair before registration:

- both shortcuts must be valid;
- the panel and Quick Capture chords must differ;
- registration must succeed before the configuration is published or persisted.

A failed registration leaves the entire published configuration and both persistence keys unchanged. Because configuration is published as one value, both settings surfaces observe one consistent snapshot. The registrar's rollback keeps the prior active chord when Carbon allows it; health reports unavailability if the rollback itself cannot restore service.

## Lifecycle and teardown

The runtime owns the coordinator and explicitly stops it during teardown. Stopping removes all workspace observers, cancels pending one-shot work, and advances the generation. Observer closures and scheduled callbacks capture weak references. Callback generation checks prevent work queued before teardown or a settings mutation from affecting current runtime state.

## Testing

Add deterministic tests that name the behavior each protects:

- wake, display-wake, and session-active bursts produce one recovery;
- successful revalidation clears panel and Quick Capture health;
- a Carbon conflict is persistent and receives no transient retry;
- a transient failure receives one bounded retry and then settles;
- one-shortcut failure leaves the other healthy and preserves the panel fallback rule;
- equal chords are rejected without registration or persistence;
- a failed settings registration publishes and persists neither candidate value;
- settings changes invalidate pending recovery callbacks;
- teardown removes observers and cancels pending work;
- stale scheduled callbacks cannot mutate health;
- registrar revalidation really uninstalls and reinstalls an unchanged chord.

Run focused shortcut/runtime tests during red-green cycles and finish with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Manual verification

Build and run the ad-hoc signed app, hide the menu-bar icon in Settings, sleep and wake the Mac, and verify both shortcuts still act without reopening Settings. Then reserve one configured chord in another app, trigger session reactivation, and verify the affected shortcut reports unavailable; if it is the panel chord, the menu-bar icon must remain visible until the conflict is removed and recovery succeeds.
