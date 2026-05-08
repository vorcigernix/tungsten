#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TUNGSTEN_VERSION:-${1:-0.1}}"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/Tungsten.app"
DIST_DIR="${ROOT_DIR}/dist"
VOLNAME="Tungsten ${VERSION}"
DMG_PATH="${DIST_DIR}/Tungsten-${VERSION}.dmg"

cd "$ROOT_DIR"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release build not found at $APP_PATH; running build-release.sh..."
  "${ROOT_DIR}/scripts/build-release.sh" -quiet
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
