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
APPCAST_URL="${APPCAST_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

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

VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")}"
BUILD_DIR="$ROOT_DIR/dist/build"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_ZIP="$RELEASE_DIR/$APP_NAME-notarize.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
UPDATE_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-macos.zip"
DMG_STAGE="$BUILD_DIR/dmg-stage"
ARM_DIR="$BUILD_DIR/arm64"
X64_DIR="$BUILD_DIR/x86_64"
UNIVERSAL_DIR="$BUILD_DIR/universal"
UNIVERSAL_PRODUCT_PATH="$UNIVERSAL_DIR/$APP_EXECUTABLE"

rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$BUILD_DIR" "$RELEASE_DIR" "$ARM_DIR" "$X64_DIR" "$UNIVERSAL_DIR"

echo "==> Building arm64 release binary"
swift build -c release --arch arm64
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/$SWIFT_PRODUCT" "$ARM_DIR/$APP_EXECUTABLE"

echo "==> Building x86_64 release binary"
swift build -c release --arch x86_64
cp "$ROOT_DIR/.build/x86_64-apple-macosx/release/$SWIFT_PRODUCT" "$X64_DIR/$APP_EXECUTABLE"

echo "==> Creating universal binary"
lipo -create "$ARM_DIR/$APP_EXECUTABLE" "$X64_DIR/$APP_EXECUTABLE" -output "$UNIVERSAL_PRODUCT_PATH"
chmod +x "$UNIVERSAL_PRODUCT_PATH"

echo "==> Assembling app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$UNIVERSAL_PRODUCT_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

# Bundle default clock art for fresh installs.
DEFAULT_CLOCK_ASSET="$ROOT_DIR/Sources/JuniperoApp/Resources/clock-reference-default.png"
if [[ -f "$DEFAULT_CLOCK_ASSET" ]]; then
  cp "$DEFAULT_CLOCK_ASSET" "$APP_BUNDLE/Contents/Resources/clock-reference-default.png"
fi

# Embed Sparkle framework when present (SwiftPM artifact path)
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -name Sparkle.framework -type d | head -n 1 || true)"
if [[ -n "${SPARKLE_FRAMEWORK:-}" && -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "==> Embedding Sparkle framework"
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  rsync -a "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
  # Ensure executable can load frameworks from Contents/Frameworks.
  install_name_tool -add_rpath @loader_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE" 2>/dev/null || true
fi

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

if [[ -n "$APPCAST_URL" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $APPCAST_URL" "$APP_BUNDLE/Contents/Info.plist" || \
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $APPCAST_URL" "$APP_BUNDLE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP_BUNDLE/Contents/Info.plist" || true
fi
if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist" || \
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist"
fi

# Strip AppleDouble and Finder metadata files that break codesign on external volumes.
find "$APP_BUNDLE" \( -name '._*' -o -name '.DS_Store' \) -delete

echo "==> Signing app"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APP_CERT" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Notarizing app"
ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "==> Building Sparkle update archive"
rm -f "$UPDATE_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$UPDATE_ZIP"

echo "==> Building DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"

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
echo "  Update ZIP: $UPDATE_ZIP"
echo "  DMG: $DMG_PATH"
