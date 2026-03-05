#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Junipero}"
OWNER_REPO="${OWNER_REPO:-$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}"
VERSION="${VERSION:-}"
TAG="${TAG:-}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
APPCAST_URL="${APPCAST_URL:-https://raw.githubusercontent.com/${OWNER_REPO}/main/appcast.xml}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"

if [[ -z "$VERSION" ]]; then
  echo "Missing VERSION (example: VERSION=1.2.3)."
  exit 1
fi

if [[ -z "$TAG" ]]; then
  TAG="v$VERSION"
fi

if [[ -z "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Missing SPARKLE_PRIVATE_KEY_FILE (path to Sparkle private Ed25519 key)."
  exit 1
fi

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "Missing SPARKLE_PUBLIC_ED_KEY (public Ed25519 key string for Info.plist)."
  exit 1
fi

if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE does not exist: $SPARKLE_PRIVATE_KEY_FILE"
  exit 1
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/${OWNER_REPO}/releases/download/${TAG}"
fi

for cmd in gh git cp; do
  command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd"; exit 1; }
done

SPARKLE_GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
  echo "Missing Sparkle generate_appcast tool at: $SPARKLE_GENERATE_APPCAST"
  echo "Run a Swift build first so Sparkle artifacts are resolved."
  exit 1
fi

UPDATE_ZIP="$ROOT_DIR/dist/release/${APP_NAME}-${VERSION}-macos.zip"
DMG_PATH="$ROOT_DIR/dist/release/${APP_NAME}-${VERSION}.dmg"
APPCAST_STAGING_DIR="$ROOT_DIR/dist/appcast"
APPCAST_FILE="$APPCAST_STAGING_DIR/appcast.xml"

export VERSION
export APPCAST_URL
export SPARKLE_PUBLIC_ED_KEY

echo "==> Building signed/notarized release artifacts"
"$ROOT_DIR/scripts/release-macos.sh"

if [[ ! -f "$UPDATE_ZIP" ]]; then
  echo "Missing update archive: $UPDATE_ZIP"
  exit 1
fi
if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH"
  exit 1
fi

echo "==> Generating Sparkle appcast"
rm -rf "$APPCAST_STAGING_DIR"
mkdir -p "$APPCAST_STAGING_DIR"
cp -f "$UPDATE_ZIP" "$APPCAST_STAGING_DIR/"

if [[ -n "$RELEASE_NOTES_FILE" && -f "$RELEASE_NOTES_FILE" ]]; then
  notes_basename="${APP_NAME}-${VERSION}-macos.md"
  cp -f "$RELEASE_NOTES_FILE" "$APPCAST_STAGING_DIR/$notes_basename"
fi

"$SPARKLE_GENERATE_APPCAST" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "https://github.com/${OWNER_REPO}" \
  -o appcast.xml \
  "$APPCAST_STAGING_DIR"

if [[ ! -f "$APPCAST_FILE" ]]; then
  echo "Failed to generate appcast: $APPCAST_FILE"
  exit 1
fi

cp -f "$APPCAST_FILE" "$ROOT_DIR/appcast.xml"

echo "==> Committing updated appcast.xml"
git add appcast.xml
if ! git diff --cached --quiet; then
  git commit -m "Update Sparkle appcast for ${VERSION}"
  git push
else
  echo "No appcast changes to commit."
fi

echo "==> Publishing GitHub release assets"
if gh release view "$TAG" --repo "$OWNER_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$UPDATE_ZIP" "$DMG_PATH" --clobber --repo "$OWNER_REPO"
else
  if [[ -n "$RELEASE_NOTES_FILE" && -f "$RELEASE_NOTES_FILE" ]]; then
    gh release create "$TAG" "$UPDATE_ZIP" "$DMG_PATH" \
      --title "${APP_NAME} ${VERSION}" \
      --notes-file "$RELEASE_NOTES_FILE" \
      --repo "$OWNER_REPO"
  else
    gh release create "$TAG" "$UPDATE_ZIP" "$DMG_PATH" \
      --title "${APP_NAME} ${VERSION}" \
      --notes "${APP_NAME} ${VERSION}" \
      --repo "$OWNER_REPO"
  fi
fi

echo
echo "Published Sparkle update for ${VERSION}."
echo "Feed URL: $APPCAST_URL"
echo "Release tag: $TAG"
