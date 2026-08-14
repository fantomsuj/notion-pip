# Perch Support

Use [GitHub Issues](https://github.com/fantomsuj/notion-pip/issues/new) for support and feedback. Include the Perch version and build shown in Settings → About, the macOS version, what you expected, and what happened. Never attach a Notion password, session cookie, integration token, private page content, signing credential, or notarization credential.

## Install a beta

Only install a Developer ID-signed, notarized Perch disk image supplied through the project's GitHub Releases page.

1. Download the Perch DMG and open it.
2. Drag Perch to Applications.
3. Eject the disk image, then open Perch from Applications.
4. Confirm macOS identifies the verified developer without asking for a Security Settings override.
5. Look for Perch in the menu bar; it intentionally does not appear in the Dock.

Do not distribute a local `dist/Perch.app` build to another Mac. Local builds may be ad-hoc signed and are not a substitute for a notarized beta.

## Common recovery steps

- **Perch launched but seems absent:** Look for the Perch menu-bar icon. If it is hidden, use the configured shortcut or the panel's edge handle.
- **Notion needs authentication:** Start sign-in from the embedded Notion interface. If Perch shows Continue in Browser, finish through the secure system-browser session and return to Perch. Perch support will never ask for your password or session cookie.
- **Launch at Login needs approval:** Open Settings → Launch at Login, follow the button to System Settings → General → Login Items & Extensions, approve Perch, then return to the app.
- **Accessibility permission appears:** Perch 0.1 does not require Accessibility access. Remove any older Perch entry in System Settings → Privacy & Security → Accessibility. If an installed 0.1 build asks for access, cancel the prompt and report the build number.

## Uninstall Perch and remove local data

1. In Perch Settings, turn off Launch at Login.
2. Quit Perch from its menu-bar or application menu.
3. Move `/Applications/Perch.app` to the Trash.
4. In System Settings → Privacy & Security → Accessibility, remove any Perch entry left by an older experimental build.
5. To remove local page history, restoration state, preferences, and embedded website data, delete Perch's containers from the current user's `~/Library/Application Support`, `~/Library/Preferences`, and `~/Library/WebKit` folders. Search for `Perch` or `com.fantomsuj.Perch` and verify each exact target before deleting it.
6. In System Settings → General → Login Items & Extensions, remove a stale Perch entry if macOS still shows one.

Deleting local data signs the embedded browser out and removes Perch's device-local history and layout. It does not delete pages or account data stored by Notion.
