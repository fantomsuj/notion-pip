# Perch Privacy Policy

_Effective August 16, 2026_

Perch is a small macOS app that displays the real Notion website in a native floating panel. Perch does not operate a cloud service, sell personal information, or include advertising or third-party analytics.

## What Perch handles

- **Your Notion session and page content:** Workspace search, editing, and page creation happen inside Notion's embedded web interface. Sign-in begins there and may continue in a secure system-browser authentication session when Notion requires it. Perch never asks you to enter a Notion password into native app UI and does not use a personal integration token. Authentication returns website cookies to WebKit's persistent website data store on this Mac so the embedded Notion session can survive relaunches. Notion receives authentication and page data under [Notion's privacy policy](https://www.notion.so/privacy).
- **Local page state:** Perch stores validated Notion page URLs and IDs, page titles, device-local pin roles, recent-page history, and best-effort restoration state such as scroll position under the current macOS user's Application Support data. Panel geometry, size presets, onboarding state, shortcut settings, and menu-bar preferences use the user's macOS Preferences. The Notion session and other website data use WebKit's website-data storage. These local stores remain on this Mac unless the user backs up or syncs their Library through another service.
- **Diagnostics:** Perch uses Apple's local unified logging and performance signposts. Private page identifiers are marked private where logged. Perch does not transmit its own diagnostics or telemetry to the developer.
- **Context Suggestions:** This optional feature uses macOS Accessibility access to read the frontmost application's name and bundle identifier, its focused window title, and a document URL when the application exposes one. Perch compares that transient context on-device with the titles and device-local roles of at most seven pinned and seven recent pages. Raw application, title, and URL context is not saved, logged, uploaded, or inserted into Notion. Dismissal suppression is stored only in memory and disappears when Perch quits.
- **System permissions:** Perch requests Accessibility access only after the user enables Context Suggestions. Disabling the setting stops that monitor immediately. Perch does not request screen-recording, microphone, camera, Contacts, or location access. Website features presented by Notion remain subject to Notion's behavior and macOS permission controls. Launch at Login is changed only when the user operates its Settings toggle.

## Quick Copy

Quick Copy is deferred from Perch 0.1. The app has no Quick Copy control and does not start its Accessibility selection monitor. Context Suggestions uses a separate monitor that does not read selected text.

The source repository retains an isolated experimental implementation for possible future testing. If a later release introduces it, the feature will require a new first-use explanation and an updated policy before release. The prototype observes selected text only while visibly armed, rejects secure fields, keeps accepted text in memory long enough to insert it at the saved Notion cursor, and does not change the clipboard or persist captured text. Accessibility access can be revoked in System Settings → Privacy & Security → Accessibility.

## Retention and deletion

Perch keeps local page and restoration state until it is replaced through normal use or the app's data is removed. To remove Perch and its local state, follow [the uninstall instructions](SUPPORT.md#uninstall-perch-and-remove-local-data). Website data for the embedded Notion session is removed with Perch's WebKit data container; signing out in Perch also ends the visible Notion session according to Notion's behavior.

## Support

Questions, privacy requests, and bug reports can be submitted through [Perch's support tracker](https://github.com/fantomsuj/notion-pip/issues/new). Do not include passwords, session cookies, private page content, or other secrets in a report.

Material changes to this policy will be published in this repository with a new effective date.
