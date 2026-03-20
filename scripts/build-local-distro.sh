#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Junipero}"
APP_EXECUTABLE="${APP_EXECUTABLE:-Junipero}"
SWIFT_PRODUCT="${SWIFT_PRODUCT:-JuniperoApp}"
BUNDLE_ID="${BUNDLE_ID:-com.junipero.app}"
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || date +%Y.%m.%d)}"
APPCAST_URL="${APPCAST_URL:-https://raw.githubusercontent.com/andrewemmelparttimepro-ux/junipero/main/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
DISTRO_DIR="${DISTRO_DIR:-$HOME/Desktop/junipero-distro}"
LEGACY_DISTRO_DIR="$HOME/Desktop/junipero_distro"

BUILD_ROOT="$ROOT_DIR/.build/local-distro"
ARM_DIR="$BUILD_ROOT/arm64"
X64_DIR="$BUILD_ROOT/x86_64"
UNIVERSAL_DIR="$BUILD_ROOT/universal"
APP_BUNDLE="$UNIVERSAL_DIR/$APP_NAME.app"
DMG_STAGE="$BUILD_ROOT/dmg-stage"
DMG_PATH="$DISTRO_DIR/$APP_NAME.dmg"
ARCHIVE_APP_PATH="$DISTRO_DIR/$APP_NAME.app"

rm -rf "$BUILD_ROOT" "$DISTRO_DIR" "$LEGACY_DISTRO_DIR"
mkdir -p "$ARM_DIR" "$X64_DIR" "$UNIVERSAL_DIR" "$DISTRO_DIR"

echo "==> Building arm64 release"
swift build -c release --arch arm64
cp ".build/arm64-apple-macosx/release/$SWIFT_PRODUCT" "$ARM_DIR/$APP_EXECUTABLE"

echo "==> Building x86_64 release"
swift build -c release --arch x86_64
cp ".build/x86_64-apple-macosx/release/$SWIFT_PRODUCT" "$X64_DIR/$APP_EXECUTABLE"

echo "==> Creating universal binary"
lipo -create "$ARM_DIR/$APP_EXECUTABLE" "$X64_DIR/$APP_EXECUTABLE" -output "$UNIVERSAL_DIR/$APP_EXECUTABLE"
chmod +x "$UNIVERSAL_DIR/$APP_EXECUTABLE"

echo "==> Assembling app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$UNIVERSAL_DIR/$APP_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

# Bundle default clock art for fresh installs.
DEFAULT_CLOCK_ASSET="$ROOT_DIR/Sources/JuniperoApp/Resources/clock-reference-default.png"
if [[ -f "$DEFAULT_CLOCK_ASSET" ]]; then
  cp "$DEFAULT_CLOCK_ASSET" "$APP_BUNDLE/Contents/Resources/clock-reference-default.png"
fi

# Embed Sparkle framework when present (SwiftPM artifact path)
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build" -name Sparkle.framework -type d | head -n 1 || true)"
if [[ -n "${SPARKLE_FRAMEWORK:-}" && -d "$SPARKLE_FRAMEWORK" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  rsync -a "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
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
  <key>SUFeedURL</key><string>$APPCAST_URL</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist" || \
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist"
fi

# Strip AppleDouble and Finder metadata files that break codesign on external volumes.
find "$APP_BUNDLE" \( -name '._*' -o -name '.DS_Store' \) -delete

echo "==> Ad-hoc signing app"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Preparing Apple-style drag-to-Applications DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"

echo "==> Copying .app into distro folder"
cp -R "$APP_BUNDLE" "$ARCHIVE_APP_PATH"

(
  cd "$DISTRO_DIR"
  shasum -a 256 "$APP_NAME.dmg" > SHA256SUMS.txt
  shasum -a 256 "$APP_NAME.app/Contents/MacOS/$APP_EXECUTABLE" >> SHA256SUMS.txt
)

file "$ARCHIVE_APP_PATH/Contents/MacOS/$APP_EXECUTABLE" > "$DISTRO_DIR/ARCH.txt"

# Keep legacy underscore folder in sync for existing workflows.
mkdir -p "$LEGACY_DISTRO_DIR"
ditto "$DISTRO_DIR/$APP_NAME.app" "$LEGACY_DISTRO_DIR/$APP_NAME.app"
cp -f "$DISTRO_DIR/$APP_NAME.dmg" "$LEGACY_DISTRO_DIR/$APP_NAME.dmg"
cp -f "$DISTRO_DIR/SHA256SUMS.txt" "$LEGACY_DISTRO_DIR/SHA256SUMS.txt"
cp -f "$DISTRO_DIR/ARCH.txt" "$LEGACY_DISTRO_DIR/ARCH.txt"

echo
echo "Local distro ready:"
echo "  $DISTRO_DIR/$APP_NAME.app"
echo "  $DISTRO_DIR/$APP_NAME.dmg"
echo "  $DISTRO_DIR/SHA256SUMS.txt"
