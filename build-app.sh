#!/bin/bash
set -euo pipefail

# ─── Thrawn Console — Build & Install as macOS .app ───
# Builds the Swift package, packages it as a proper .app bundle,
# and installs to ~/Applications so Spotlight can find it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="Thrawn"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

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
RESOURCE_BUNDLE="$BUILD_DIR/ThrawnApp_ThrawnApp.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "  ✓ Resources bundle copied"
fi

# ── Step 7: Ad-hoc code sign ──
echo "▸ Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
echo "  ✓ Code signed (ad-hoc)"

# ── Step 8: Install to ~/Applications ──
echo "▸ Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
echo "  ✓ Installed to $INSTALL_DIR/$APP_NAME.app"

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
