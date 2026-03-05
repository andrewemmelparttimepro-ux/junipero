#!/usr/bin/env bash
set -euo pipefail

# End-to-end macOS release pipeline:
# 1) Build release binary
# 2) Assemble .app bundle
# 3) Sign app
# 4) Notarize + staple app
# 5) Build DMG
# 6) Notarize + staple DMG

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Junipero}"
BUNDLE_ID="${BUNDLE_ID:-ai.junipero.app}"
APP_EXECUTABLE="${APP_EXECUTABLE:-Junipero}"
SWIFT_PRODUCT="${SWIFT_PRODUCT:-JuniperoApp}"
DEVELOPER_ID_APP_CERT="${DEVELOPER_ID_APP_CERT:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$DEVELOPER_ID_APP_CERT" ]]; then
  echo "Missing DEVELOPER_ID_APP_CERT env var."
  echo "Example: export DEVELOPER_ID_APP_CERT='Developer ID Application: Your Name (TEAMID)'"
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Missing NOTARY_PROFILE env var."
  echo "Create once with:"
  echo "xcrun notarytool store-credentials <profile-name> --apple-id <id> --team-id <team> --password <app-password>"
  exit 1
fi

for cmd in swift xcrun codesign hdiutil ditto; do
  command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd"; exit 1; }
done

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")"
BUILD_DIR="$ROOT_DIR/dist/build"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_ZIP="$RELEASE_DIR/$APP_NAME-notarize.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
PRODUCT_PATH="$ROOT_DIR/.build/release/$SWIFT_PRODUCT"

rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

echo "==> Building release binary"
swift build -c release

if [[ ! -f "$PRODUCT_PATH" ]]; then
  echo "Release product not found at $PRODUCT_PATH"
  exit 1
fi

echo "==> Assembling app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$PRODUCT_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_EXECUTABLE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing app"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APP_CERT" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Notarizing app"
ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "==> Building DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

echo "==> Signing DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APP_CERT" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Gatekeeper check"
spctl -a -vv "$APP_BUNDLE" || true

echo
echo "Release complete:"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
