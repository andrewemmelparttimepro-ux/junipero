# macOS Signing + Notarization Guide

## Goal
Produce a macOS build that opens cleanly on end-user Macs without Gatekeeper bypass steps.

## Prerequisites
- Apple Developer Program membership (Developer ID certificate access).
- Xcode command line tools.
- `notarytool` credentials saved to keychain.

## One-Time Setup
1. Install your `Developer ID Application` certificate in Keychain.
2. Save notarization credentials:
```bash
xcrun notarytool store-credentials junipero-notary \
  --apple-id "<APPLE_ID_EMAIL>" \
  --team-id "<TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

## Build + Sign + Notarize + Staple
From repo root:
```bash
export DEVELOPER_ID_APP_CERT="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="junipero-notary"
export APPCAST_URL="https://raw.githubusercontent.com/andrewemmelparttimepro-ux/junipero/main/appcast.xml"
./scripts/release-macos.sh
```

Artifacts are written to `dist/release/`.

## What This Script Does
1. Builds release binary from Swift package.
2. Assembles `.app` bundle.
3. Signs app with hardened runtime + timestamp.
4. Notarizes and staples app.
5. Creates DMG.
6. Signs, notarizes, and staples DMG.

## Can We Avoid the Apple Developer Fee?
Short answer: not for seamless public distribution.

- For clean end-user install experience (no warnings/bypass), you need Developer ID signing + notarization.
- Developer ID/notarization requires paid Apple Developer Program membership.

### What you can do without paying
- Share unsigned/ad-hoc builds for technical testers.
- Users can right-click `Open` and bypass warnings manually.
- Users can build from source locally.

## Sparkle In-App Updates
- Packaged builds write `SUFeedURL` into app `Info.plist` (from `APPCAST_URL`).
- Sparkle requires signed appcast enclosures (`sparkle:edSignature`) to install updates from `Check for Updates`.

### One-command publish flow (recommended)
Use the publisher script to:
1. Build + sign + notarize release artifacts.
2. Generate Sparkle-signed `appcast.xml`.
3. Commit/push updated `appcast.xml`.
4. Upload release assets to GitHub tag release.

```bash
export DEVELOPER_ID_APP_CERT="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="junipero-notary"
export SPARKLE_PUBLIC_ED_KEY="<Sparkle public key>"
export SPARKLE_PRIVATE_KEY_FILE="$HOME/.config/junipero/sparkle_private_ed25519.pem"

VERSION=1.0.1 ./scripts/publish-sparkle-update.sh
```

Optional:
- `TAG=v1.0.1` override release tag (defaults to `v$VERSION`).
- `RELEASE_NOTES_FILE=./notes/1.0.1.md` attach notes to GitHub release and appcast item.
- `OWNER_REPO=andrewemmelparttimepro-ux/junipero` override detected GitHub repo.

After this, in-app `Check for Updates` pulls from `appcast.xml` and installs the new build.

These options are fine for testing, not for polished public release.
