# Retain Notion Editor Selection Across PiP Restore

## Goal

When the global shortcut restores a stashed Notion PiP panel, return keyboard
focus and the user's previous cursor or text selection in the same Notion page
when its existing `WKWebView` is still retained in memory.

## Scope

- Capture a selection only from a live editable element in the trusted Notion
  main frame as the panel is suspended.
- Restore it after the same retained web view is attached to the visible panel.
- Fall back to normal web-page focus if no selection was captured or the saved
  DOM range can no longer be resolved.
- Discard saved selection data whenever navigation, a page change, reload, or
  web-view eviction makes it stale.

The selection is intentionally not persisted across a fresh load. Existing
opaque `WKWebView` interaction-state restoration remains responsible for its
current reload recovery behavior.

## Design

`NotionWebSession` will use small, one-shot JavaScript evaluations to serialize
the anchor and focus endpoints of the active DOM selection as paths relative to
the containing editable element. The native side stores this snapshot with the
currently loaded page identity only after capture completes while the panel is
still hidden.

On panel restoration, the session will first reattach the retained web view.
It will then request focus and evaluate a restore script that validates the
same editable element and reconstructs the range. If validation or restoration
fails, the session focuses the web view without applying a selection. No
background polling, observers, or cross-page persistence is introduced.

## Lifecycle and Error Handling

- A pending capture must not suspend the web view if the panel is shown again
  before the evaluation returns.
- Restoring selection is attempted only for the matching retained page and
  never after web-view eviction or navigation.
- JavaScript errors, malformed snapshots, DOM replacement by Notion, and an
  absent editable area all use the normal-focus fallback without surfacing an
  error to the user.

## Verification

Unit tests will cover capture-and-restore on a retained page, invalid or
missing selection fallback, and invalidation on navigation, reload, page
replacement, and eviction. The full Swift test suite will validate the final
change.
