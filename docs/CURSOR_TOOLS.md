# Cursor tools

The pointer is the one thing that is in every app, so Perch uses it for jobs
that cross apps. Both tools are off until you turn on **Settings → Cursor
Tools**.

## Carry a screenshot

1. Press **Control-Option-Command-S** and select an area (Space switches to a
   window, Escape cancels). This is macOS's own screenshot picker.
2. A thumbnail rides beside the pointer. Keep working; it follows you across
   apps, Spaces, and displays.
3. **Double-click** where it should go to drop it:
   - in the Perch page, it is pasted into Notion at the spot you clicked, and
     Notion uploads it like any pasted image;
   - in any other app (Slack, Mail, Figma, a Finder window…), it is pasted
     there.
4. **Shake** the pointer to toss it instead. Pressing the shortcut again while
   carrying swaps in a new screenshot.

Dropping borrows the clipboard for about a second and then puts back what you
had copied, unless you copied something new in the meantime.

The second click of the drop's double-click is held back, so the target app
sees a single click that places the cursor rather than a double-click that
selects a word.

## Jot a margin note

1. Press **Control-Option-Command-N** in any app. A small card opens at the
   pointer. The app underneath stays in front.
2. Type the note. **Return** saves, **Escape** cancels. Clicking away saves
   what you typed.
3. The note lands in the open Perch page, where the Notion cursor last was, as
   one bullet that keeps the time and source:

   ```markdown
   - Ask about rate limits — _Safari · [Rate limits](https://docs.stripe.com/rate-limits) · Nov 7, 11:42 AM_
   ```

   The source is the app in front, plus its window title and document (a page
   URL in Safari, a file in most document apps) when Accessibility is allowed.

If the Perch page has no cursor yet (for example right after switching pages)
or no page is loaded, the note waits on this Mac. The next note you save brings
waiting notes along in order, or use **Settings → Cursor Tools → Drop into
Notion** after clicking where they should go. **Copy** puts them on the
clipboard as Markdown, and **Clear** discards them.

## Permissions

| Permission | Asked when | Used for | Without it |
|---|---|---|---|
| Screen Recording | First screenshot | macOS requires it for `screencapture` | No screenshot can be taken |
| Accessibility | Turning cursor tools on | Holding back the drop's second click and pressing Command-V in other apps; reading the front window's title and document for notes | Drops in Perch still work. Drops in other apps copy the image and ask you to press Command-V. Notes keep only the app name. |

Perch only watches the pointer while a screenshot is being carried, and only
reads window details at the moment a note card opens. It never reads selected
text or typing in other apps. See [PRIVACY.md](PRIVACY.md).

## How it works

- `CursorToolsController` owns the setting and the two global shortcuts
  (Carbon hot keys, like Perch's main shortcut).
- `CursorCarryController` runs `/usr/sbin/screencapture -i -x`, shows the
  thumbnail in a click-through panel, and follows the pointer. With
  Accessibility it uses a session event tap, which can hold back the drop's
  second click and stays active only while carrying. Without it, a local event
  monitor handles Perch's own windows and a global monitor watches other apps.
  `CursorShakeDetector` counts quick direction reversals on either axis.
- `MarginNoteController` shows the note card in a non-activating panel, reads
  the source with `MarginNoteSourceReader`, and pastes Markdown through the same
  saved-cursor path that local agent streaming uses
  (`NotionWebSession.pasteMarkdownAtSavedEditorCursor`).

## Shortcuts

The shortcuts are fixed for now. If another app already uses one, Settings
says so.
