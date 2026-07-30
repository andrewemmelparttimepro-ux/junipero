# Thrawn Release Signing

This repo's everyday local install path is:

```bash
./build-app.sh
```

That builds, bundles, signs with the persistent local identity `NDAI Local App Signing`, and installs `/Applications/Thrawn.app`. Keeping the identity stable prevents Keychain authorization prompts from returning after every rebuild.

Thrawn's provider-agent build intentionally runs outside App Sandbox because it must launch official provider CLIs and give those agents access to operator-selected project workspaces. Use the signed Developer ID/notarized distribution path for external releases; do not submit this runtime-host build to the Mac App Store sandbox.

For a notarized external release, configure:

```bash
export DEVELOPER_ID_APP_CERT="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="thrawn-notary"
export APP_NAME="Thrawn"
export APP_EXECUTABLE="ThrawnApp"
export SWIFT_PRODUCT="ThrawnApp"
export BUNDLE_ID="com.thrawn.console"
export APPCAST_URL="https://example.com/thrawn/appcast.xml"
```

Then run:

```bash
scripts/release-macos.sh
```

Sparkle appcast publishing remains optional and requires a private Ed25519 key supplied by `SPARKLE_PRIVATE_KEY_FILE`. Never commit signing keys, app-specific passwords, keychain exports, or notarization credentials.
