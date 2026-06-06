#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TUNGSTEN_VERSION:-${1:-0.11}}"
BUILD_NUMBER="${TUNGSTEN_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/Tungsten.app"
APP_ARTI_BIN="${APP_PATH}/Contents/Resources/Arti/arti"
DIST_DIR="${ROOT_DIR}/dist"
VOLNAME="Tungsten ${VERSION}"
DMG_PATH="${DIST_DIR}/Tungsten-${VERSION}.dmg"

cd "$ROOT_DIR"

echo "Building release app for package..."
TUNGSTEN_VERSION="$VERSION" TUNGSTEN_BUILD_NUMBER="$BUILD_NUMBER" \
  "${ROOT_DIR}/scripts/build-release.sh" -quiet

if [[ ! -x "$APP_ARTI_BIN" ]]; then
  echo "Release build is missing bundled Arti at $APP_ARTI_BIN; rebuilding..."
  TUNGSTEN_VERSION="$VERSION" TUNGSTEN_BUILD_NUMBER="$BUILD_NUMBER" \
    "${ROOT_DIR}/scripts/build-release.sh" -quiet
fi

if [[ ! -x "$APP_ARTI_BIN" ]]; then
  echo "Cannot package Tungsten without bundled Arti at $APP_ARTI_BIN." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

STAGING="$(mktemp -d -t tungsten-dmg)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP_PATH" "${STAGING}/Tungsten.app"
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH" >/dev/null

SIZE_HUMAN="$(du -h "$DMG_PATH" | awk '{print $1}')"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

cat <<EOF

Built: $DMG_PATH  (${SIZE_HUMAN}, sha256 ${SHA256})

Friends' install steps (ad-hoc signed, arm64 only):
  1. Open the .dmg and drag Tungsten into Applications.
  2. First launch will be blocked by Gatekeeper.
     Open System Settings → Privacy & Security, scroll down, click
     "Open Anyway" next to the Tungsten warning, then confirm.
  3. If their browser stamped the file with a quarantine bit and
     "Open Anyway" still won't appear, they can run:
       xattr -dr com.apple.quarantine /Applications/Tungsten.app
EOF
