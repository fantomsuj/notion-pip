# Direct macOS Distribution

Perch is distributed outside the Mac App Store as a Universal 2 disk image.
The release artifact contains a Developer ID-signed, hardened-runtime app and
an `/Applications` symlink. Its Finder window presents the app and Applications
shortcut beneath a clear drag-to-install instruction. Apple notarizes the disk
image, and the release pipeline staples the resulting ticket before publication.

The development build remains intentionally separate. Running
`script/build_and_run.sh` may use an Apple Development, local-development, or
ad-hoc identity and never produces a public release artifact.

## One-time Apple setup

1. Enroll the release owner in the Apple Developer Program.
2. Create a **Developer ID Application** certificate. A Developer ID Installer
   certificate is not needed because Perch ships in a DMG rather than a PKG.
3. Install the certificate and its private key in the login keychain.
4. Create an App Store Connect API key with notarization access, or save Apple
   ID notarization credentials in the local keychain:

   ```sh
   xcrun notarytool store-credentials "Perch Notarization" \
     --apple-id "YOUR_APPLE_ID" \
     --team-id "YOUR_TEAM_ID"
   ```

   `notarytool` prompts for an app-specific password. Do not place the password,
   certificate, private key, or stored credential in this repository.

## Package a release locally

Update `Support/Version.env` first. `PERCH_VERSION` is the user-facing semantic
version and `PERCH_BUILD_NUMBER` must increase for every distributed build.

With a local notarytool profile:

```sh
PERCH_NOTARY_KEYCHAIN_PROFILE="Perch Notarization" \
  ./script/package_release.sh
```

The script automatically selects an installed Developer ID Application
identity. Set `PERCH_DISTRIBUTION_SIGNING_IDENTITY` to its certificate hash or
full name if the keychain contains more than one suitable identity.

The script performs these release gates:

1. Cross-compiles release executables for `arm64` and `x86_64`.
2. Combines and verifies the two slices as one Universal 2 executable.
3. Stages `Perch.app` in an isolated release workspace with the release version,
   icon, and resources.
4. Embeds Sparkle and signs its XPC services, helper, updater app, framework,
   and the Perch app inside-out with Developer ID, hardened runtime, secure
   timestamps, and component-appropriate entitlements.
5. Builds and signs `Perch-VERSION.dmg` with a guided drag-to-Applications
   Finder layout. The code-authored vector artwork in `Support/` is rendered at
   1× and 2× and packaged as a multi-resolution Finder background.
6. Submits the DMG to Apple, waits for acceptance, staples the ticket, and
   validates it with `stapler`, `hdiutil`, and Gatekeeper.
7. Writes `dist/Perch-VERSION.dmg.sha256`.

The script moves the DMG into `dist/` only after every signing, notarization,
stapling, disk-image, and Gatekeeper check succeeds. A failed run cannot replace
an existing release artifact with an unvalidated image.

The release script has explicit inside-out signing rules for Sparkle's bundled
XPC services, `Autoupdate` helper, updater app, and framework. It rejects every
other nested framework, XPC service, app extension, nested app, or dynamic
library until a component-specific signing rule is added. Do not replace this
gate with `codesign --deep`.

## Sparkle update signing

Sparkle reads its public configuration from `Support/Sparkle.env`. The appcast
is served from `https://pinapage.com/appcast.xml`, which redirects to the
`appcast.xml` asset on the latest published GitHub release. Both Sparkle and the
website use the same notarized DMG.

The matching Ed25519 private key belongs in the release owner's Keychain and in
the `SPARKLE_ED_PRIVATE_KEY` GitHub secret. Never commit it. To export a backup
with the package-resolved Sparkle tool:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.fantomsuj.Perch \
  -x Perch-Sparkle-Ed25519-private-key.txt
```

Treat the exported file like a password. The release workflow pipes the secret
to `generate_appcast` over standard input and publishes the resulting signed
feed beside the DMG.

## GitHub release automation

Create a GitHub Actions environment named `release`, protect it with required
reviewers, and add these environment secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `RELEASE_KEYCHAIN_PASSWORD` | Random password for the workflow's temporary keychain |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-encoded App Store Connect `.p8` API key |
| `APP_STORE_CONNECT_KEY_ID` | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer ID |
| `SPARKLE_ED_PRIVATE_KEY` | Exported Sparkle Ed25519 private key |

Encode the two files without printing their contents into terminal history:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

After merging a release commit, create and push a tag that exactly matches
`PERCH_VERSION`:

```sh
git tag -s v0.1.1 -m "Perch 0.1.1"
git push origin v0.1.1
```

The `Release notarized DMG` workflow reruns the tests, imports credentials into
an ephemeral keychain, packages and notarizes the DMG, generates the signed
appcast, preserves the artifacts, and creates a **draft** GitHub Release.
Inspect its generated notes, DMG, checksum, and appcast before publishing it. A
failed build never creates a public release.

## Final release validation

Before publishing the draft release:

- Download the DMG through a browser on a Mac that did not build Perch.
- Confirm the disk image opens with the guided layout and Perch can be dragged
  to Applications.
- Launch the installed copy and confirm Gatekeeper identifies the verified
  developer without requiring a Security Settings override.
- Complete the critical tests in `docs/BETA_READINESS.md`, including Notion
  sign-in and a real Launch at Login logout/login cycle. Perch 0.1 must not
  request Accessibility permission; remove any grant retained from an older
  experimental build before testing.
- Confirm the version and SHA-256 checksum shown in the release.
- Install the preceding signed release, choose **Check for Updates…**, and
  complete an in-place update to this release. Confirm Perch relaunches with the
  new `CFBundleVersion`, preserves its pinned pages, and still passes
  `codesign --verify --deep --strict`.
