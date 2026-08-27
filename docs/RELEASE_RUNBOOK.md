# Release runbook

The per-release checklist for shipping a notarized Perch DMG. This is the short
operational companion to [Direct Distribution](DISTRIBUTION.md), which has the
full certificate, secret, and signing detail. Run this alongside
[External Beta Readiness](BETA_READINESS.md).

## Prerequisites (verified once)

- Apple Developer Program enrollment is active.
- A **Developer ID Application** certificate and its private key are installed
  locally, or exported as a base64 `.p12` in the `DEVELOPER_ID_CERTIFICATE_BASE64`
  secret.
- An App Store Connect API key with notarization access exists, with its `.p8`
  in `APP_STORE_CONNECT_API_KEY_BASE64`.
- The Sparkle Ed25519 private key is in the `SPARKLE_ED_PRIVATE_KEY` secret and
  its public counterpart is committed in `Support/Sparkle.env`.
- The GitHub Actions `release` environment exists, is protected with required
  reviewers, and has all seven secrets listed in
  [DISTRIBUTION.md](DISTRIBUTION.md#github-release-automation).
- The `https://pinapage.com/appcast.xml` redirect points at the latest GitHub
  release `appcast.xml` asset. See
  [Appcast redirect setup](DISTRIBUTION.md#appcast-redirect-setup).

## Every release

### 1. Bump the version

Edit `Support/Version.env`:

- Set `PERCH_VERSION` to the user-facing semantic version (three numeric
  components, e.g. `0.1.2`).
- **Increment `PERCH_BUILD_NUMBER`** to a positive integer higher than every
  previous distributed build. This is what macOS and Sparkle use to decide
  whether an update is newer — re-shipping the same build number means nobody
  receives the update.

Commit and merge to `master`.

### 2. Tag and push

The tag name must be `v` + `PERCH_VERSION` exactly:

```sh
git tag -s v0.1.2 -m "Perch 0.1.2"
git push origin v0.1.2
```

If the tag and `Version.env` disagree, the workflow fails at its first step.

### 3. Wait for the workflow

The `Release notarized DMG` workflow on GitHub Actions:

1. Validates the tag and build number.
2. Runs the full test suite and script tests.
3. Installs credentials in an ephemeral keychain.
4. Builds a Universal 2 binary, signs it with Developer ID + hardened runtime,
   and signs Sparkle's nested components inside-out.
5. Packages the DMG with a guided drag-to-Applications layout.
6. Notarizes the DMG, staples the ticket, and validates with Gatekeeper.
7. Generates the signed Sparkle appcast (`dist/appcast.xml`).
8. Creates a **draft** GitHub Release with the DMG, checksum, and appcast.

A failed build never creates a public release.

### 4. Validate on a clean Mac

Before publishing the draft:

- Download the DMG through a browser on a Mac that did not build Perch.
- Open the disk image and confirm the drag-to-Applications layout.
- Drag Perch to Applications and launch it.
- Confirm Gatekeeper identifies the verified developer without a Security
  Settings override.
- Verify the version and build in Settings → About.
- Verify the SHA-256 checksum against the `.sha256` file.
- Run the ten critical manual tests in
  [BETA_READINESS.md](BETA_READINESS.md#ten-critical-manual-tests).
- Install the preceding signed release, choose **Check for Updates…**, and
  complete an in-place update to this release. Confirm Perch relaunches with
  the new `CFBundleVersion`, preserves pinned pages, and still passes
  `codesign --verify --deep --strict`.

### 5. Publish

On the draft GitHub release:

1. Review the auto-generated notes and add any manual notes.
2. Click **Publish release**.

Publishing makes the assets publicly downloadable and, through the
`pinapage.com/appcast.xml` redirect, immediately becomes the update target for
every running copy of Perch. There is no separate appcast deployment step.

### 6. Confirm auto-update is live

After publishing, verify that
`https://pinapage.com/appcast.xml` redirects to the new release's `appcast.xml`
and that the feed references the new DMG and version. An installed copy of the
previous release should report the update within its next Sparkle check
interval.

## If something fails

- **Workflow fails before packaging:** fix the issue, bump `PERCH_BUILD_NUMBER`
  if you already pushed a tag, delete the old tag, re-tag, and push again.
- **Workflow succeeds but validation fails on a clean Mac:** do not publish the
  draft. Delete the draft release, fix the issue, bump `PERCH_BUILD_NUMBER`,
  re-tag, and push again.
- **Published release has a defect:** there is no automatic rollback. Ship a
  new build with an incremented `PERCH_BUILD_NUMBER` and a corrected tag. Do
  not delete or force-push a published tag — installed copies may have already
  cached its appcast entry.
