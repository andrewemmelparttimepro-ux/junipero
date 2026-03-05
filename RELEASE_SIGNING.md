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

These options are fine for testing, not for polished public release.
