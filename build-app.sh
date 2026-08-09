#!/bin/bash
set -euo pipefail

# ─── Thrawn Console — Build & Install as macOS .app ───
# Builds the Swift package, packages it as a proper .app bundle,
# and installs to /Applications so Spotlight can find it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="Thrawn"
PACKAGE_ROOT="$(mktemp -d /tmp/thrawn-app-build.XXXXXX)"
APP_BUNDLE="$PACKAGE_ROOT/$APP_NAME.app"
INSTALL_DIR="/Applications"
LOCAL_SIGNING_IDENTITY="${LOCAL_SIGNING_IDENTITY:-NDAI Local App Signing}"

cleanup_package_root() {
    rm -rf "$PACKAGE_ROOT"
}
trap cleanup_package_root EXIT

sign_app_bundle() {
    local bundle="$1"
    find "$bundle" \( -name '.DS_Store' -o -name '._*' \) -delete 2>/dev/null || true
    xattr -cr "$bundle" 2>/dev/null || true
    xattr -dr com.apple.FinderInfo "$bundle" 2>/dev/null || true
    xattr -dr 'com.apple.fileprovider.fpfs#P' "$bundle" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "$bundle" 2>/dev/null || true
    if ! security find-identity -v -p codesigning "$HOME/Library/Keychains/login.keychain-db" | grep -Fq "\"$LOCAL_SIGNING_IDENTITY\""; then
        echo "Missing local code-signing identity: $LOCAL_SIGNING_IDENTITY" >&2
        echo "Install the persistent local identity before building so Keychain permissions survive app updates." >&2
        exit 1
    fi
    codesign --force --deep --sign "$LOCAL_SIGNING_IDENTITY" "$bundle"
    codesign --verify --deep --strict "$bundle"
}

echo "═══════════════════════════════════════"
echo "  THRAWN — Build & Install"
echo "═══════════════════════════════════════"
echo ""

# ── Step 1: Build release binary ──
echo "▸ Building release binary..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1
echo "  ✓ Build complete"

# ── Step 2: Create .app bundle structure ──
echo "▸ Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ── Step 3: Copy executable ──
cp "$BUILD_DIR/ThrawnApp" "$APP_BUNDLE/Contents/MacOS/ThrawnApp"
echo "  ✓ Executable copied"

# ── Step 4: Copy Info.plist ──
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
echo "  ✓ Info.plist copied"

# ── Step 5: Generate .icns from existing PNG icons ──
ICON_SRC="$SCRIPT_DIR/Sources/ThrawnApp/Resources/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="$SCRIPT_DIR/.build/AppIcon.iconset"

if [ -f "$ICON_SRC/app_icon_1024.png" ]; then
    echo "▸ Generating app icon..."
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    # macOS iconset expects specific filenames
    cp "$ICON_SRC/app_icon_16.png" "$ICONSET_DIR/icon_16x16.png"
    cp "$ICON_SRC/app_icon_32.png" "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ICON_SRC/app_icon_32.png" "$ICONSET_DIR/icon_32x32.png"
    cp "$ICON_SRC/app_icon_64.png" "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ICON_SRC/app_icon_128.png" "$ICONSET_DIR/icon_128x128.png"
    cp "$ICON_SRC/app_icon_256.png" "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ICON_SRC/app_icon_256.png" "$ICONSET_DIR/icon_256x256.png"
    cp "$ICON_SRC/app_icon_512.png" "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ICON_SRC/app_icon_512.png" "$ICONSET_DIR/icon_512x512.png"
    cp "$ICON_SRC/app_icon_1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    echo "  ✓ App icon generated"
else
    echo "  ⚠ No icon source found, skipping icon generation"
fi

# ── Step 6: Copy Resources bundle (if built by SPM) ──
RESOURCE_BUNDLE=""
for candidate in \
    "$BUILD_DIR/ThrawnApp_ThrawnApp.bundle" \
    "$SCRIPT_DIR/.build/arm64-apple-macosx/release/ThrawnConsole_ThrawnApp.bundle" \
    "$SCRIPT_DIR/.build/x86_64-apple-macosx/release/ThrawnConsole_ThrawnApp.bundle"
do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done
if [ -n "$RESOURCE_BUNDLE" ]; then
    ditto --norsrc --noextattr "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
    echo "  ✓ Resources bundle copied"
else
    echo "Missing SwiftPM resource bundle for ThrawnApp" >&2
    exit 1
fi

# ── Step 6b: Bundle OpsBundle into the .app's Resources ──
# Without this, the runtime opsBundleDir lookup falls back to walking the
# source tree — which fails on installed builds when ~/Documents/ is in a
# TCC-protected location and the app hasn't been granted Full Disk Access.
# Bundling the source-of-truth files into the .app makes deployment
# self-contained: opsBundleDir resolves to Bundle.main.resourceURL/OpsBundle
# every time, sandbox or no sandbox.
OPSBUNDLE_SRC="$SCRIPT_DIR/OpsBundle"
if [ -d "$OPSBUNDLE_SRC" ]; then
    ditto --norsrc --noextattr "$OPSBUNDLE_SRC" "$APP_BUNDLE/Contents/Resources/OpsBundle"
    echo "  ✓ OpsBundle bundled ($(find "$OPSBUNDLE_SRC" -type f | wc -l | tr -d ' ') files)"
else
    echo "  ⚠ No OpsBundle source found at $OPSBUNDLE_SRC — runtime will fall back to dev-tree lookup"
fi

# ── Step 7: Stable local code sign ──
echo "▸ Code signing..."
sign_app_bundle "$APP_BUNDLE"
echo "  ✓ Code signed (stable local identity)"

# ── Step 8: Install to /Applications ──
echo "▸ Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
ditto --norsrc --noextattr "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
echo "  ✓ Installed to $INSTALL_DIR/$APP_NAME.app"

echo "▸ Verifying installed app signature..."
sign_app_bundle "$INSTALL_DIR/$APP_NAME.app"
echo "  ✓ Installed signature verified"

# ── Step 9: Touch Spotlight index ──
echo "▸ Updating Spotlight index..."
mdimport "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
echo "  ✓ Spotlight notified"

echo ""
echo "═══════════════════════════════════════"
echo "  ✓ Thrawn installed successfully!"
echo ""
echo "  Search 'Thrawn' in Spotlight (⌘Space)"
echo "  or open: $INSTALL_DIR/$APP_NAME.app"
echo "═══════════════════════════════════════"
