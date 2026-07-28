# macOS Windowing Manual Test Matrix

Use a development build from `dist/NotionPiP.app`. Before each row, pin a Notion page and confirm that typing in the PiP works. Record observed behavior in **Actual Result**, then mark **Pass/Fail**.

| Environment | Action | Expected Result | Actual Result | Pass/Fail | Notes |
|---|---|---|---|---|---|
| Stage Manager off; one display; separate Spaces on | Launch with no saved PiP frame or panel-size preferences, place the pointer on the display, and restore a saved pinned page at startup | App activates; PiP becomes key at the adaptive Comfortable content size, 24 pt from the visible top-right corner; page remains editable |  |  |  |
| Stage Manager on; one display; separate Spaces on | Toggle the PiP from the menu bar, then hide and show it again | Every show activates the app and makes the retained PiP key without reloading the page |  |  |  |
| Stage Manager off; two displays; separate Spaces on | Remove the PiP autosaved frame, place the pointer on the secondary display, and show the PiP with the shortcut | First-use PiP appears on the pointer’s display, 24 pt from that display’s visible top-right corner |  |  |  |
| Stage Manager on; two displays; separate Spaces on | Move the pointer into the secondary display’s menu bar and show a first-use PiP | Full screen geometry selects the secondary display; visible geometry keeps the PiP below its menu bar |  |  |  |
| Stage Manager off; two displays; separate Spaces off | Show, hide, and restore the PiP from the menu bar and shortcut on each display | PiP activates and becomes key on every presentation; retained WebView state and editing survive |  |  |  |
| Full-screen app on primary display | Present the PiP from the menu bar and edit the page | PiP joins the full-screen Space as an auxiliary floating overlay and accepts keyboard input |  |  |  |
| Full-screen app on secondary display | Place pointer on secondary display, present a first-use PiP, and edit the page | PiP opens on the secondary full-screen Space, floats above the app, and becomes key |  |  |  |
| PiP visible | Open Mission Control | PiP is absent from Mission Control while remaining visible as an overlay when Mission Control closes |  |  |  |
| PiP visible and key; another app has multiple windows | Press Command-` repeatedly | PiP is excluded from the window cycle; returning to it directly still supports editing |  |  |  |
| PiP stashed; stash handle visible | Open Mission Control, then press Command-` repeatedly | Stash handle is absent from Mission Control and excluded from window cycling |  |  |  |
| PiP stashed | Click the stash handle | App activates; same retained PiP and WebView return as the key window without a page reload |  |  |  |
| Dock on left edge | First-use show, move, stash, and restore the PiP | Placement and clamping use the visible frame; PiP and handle do not overlap the Dock unintentionally |  |  |  |
| Dock on right edge | First-use show, move, stash, and restore the PiP | Top-right inset is measured from the visible frame; PiP and handle stay inside usable geometry |  |  |  |
| Dock on bottom edge | First-use show, resize to minimum, stash, and restore the PiP | PiP remains at least 360×420 when space permits and stays above the Dock |  |  |  |
| PiP visible on secondary display | Unplug the secondary monitor | Visible PiP reclamps into an available display and remains editable with retained page state |  |  |  |
| PiP visible after monitor unplug | Reconnect the secondary monitor | PiP remains valid and visible; no duplicate window or page reload occurs |  |  |  |
| PiP manually sized on a large display | Move it to a smaller display, then reconnect or return to the large display | PiP temporarily clamps to usable space without replacing the preferred working size, then restores the preferred size when space permits |  |  |  |
| PiP stashed on secondary display | Unplug the secondary monitor | Main PiP frame is retained for restoration; visible stash handle snaps to an available display edge |  |  |  |
| PiP stashed after monitor unplug | Reconnect the secondary monitor, then click the handle | Same PiP session restores, geometry is clamped to an available screen, and the page does not reload |  |  |  |
| Fresh install with a pinned page | Launch once with no autosaved frame or panel-size preference | Comfortable is marked Default and is used for first presentation without disabling manual resizing |  |  |  |
| Existing install with autosaved geometry | Upgrade and launch with no panel-size preference | Existing autosaved content size and placement remain unchanged |  |  |  |
| Settings → Panel Sizes | Change Default Size between Compact, Comfortable, Wide, and a custom preset | Default marker changes, but the visible PiP does not resize until Apply Default or Reset to Default Size is chosen |  |  |  |
| Settings → Panel Sizes | Save the retained PiP's current size, edit its name and dimensions, then apply it | A unique 1–40 character preset is saved with whole-point dimensions and applying it resizes the retained PiP |  |  |  |
| Settings → Panel Sizes | Rename and resize a custom preset, then delete it while it is the default | Edits do not resize the PiP; deletion removes the row, changes the default to Comfortable, and does not resize immediately |  |  |  |
| Settings → Panel Sizes | Create 12 custom presets, then try to create another or reuse a name | The thirteenth preset and duplicate name are rejected with clear inline guidance; existing presets remain unchanged |  |  |  |
| PiP ellipsis and status-item right-click menus | Apply each built-in and custom preset from both menus | Both menus show the same order and Default suffix, apply identical content sizes, and preserve the nearest screen-edge anchoring |  |  |  |
| PiP hidden or stashed with an edited Notion page | Apply a preset from Settings or Reset to Default Size | The retained PiP restores and becomes visible at the requested effective size without reloading the page or losing selection and edits |  |  |  |
| No page pinned | Open Settings and both panel-size menus where available | Defaults and presets remain manageable in Settings; Apply actions are disabled until a PiP exists |  |  |  |
| Small display with oversized custom preset | Apply the preset, then move the PiP to a display large enough for it | Effective frame is clamped safely on the small display; stored dimensions remain unchanged and restore on the larger display |  |  |  |
| Keyboard navigation and Full Keyboard Access | Manage, choose, apply, and delete presets without a pointer | Focus order is logical, every action is reachable, and destructive actions are clearly labeled |  |  |  |
| VoiceOver enabled | Navigate current size, default picker, preset rows, and both Panel Size submenus | Names, dimensions, Default state, enabled state, and Apply/Delete actions are announced unambiguously |  |  |  |
| Notion editing at Compact, Comfortable, Wide, and a custom size | Edit text, change selection, apply another size, stash, and restore | Notion remains editable and keeps the same WebView, page, selection, and session throughout |  |  |  |
| Quick Capture open | Resize toward the minimum, switch Spaces, close, and reopen from the app command | Window stops at 440×400, follows the active Space, activates as key, and retains its presenter state |  |  |  |
| Settings open | Resize toward the minimum, switch Spaces, close, and reopen | Normal-level window stops at 440×420, follows the active Space, activates as key, and is retained |  |  |  |
| Pin Page open | Attempt to resize, switch Spaces, close, and reopen with no page pinned | Window remains fixed at 440×180, follows the active Space, activates as key, and focuses URL entry |  |  |  |
