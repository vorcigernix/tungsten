#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TUNGSTEN_VERSION:-${1:-0.12}}"
BUILD_NUMBER="${TUNGSTEN_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/Tungsten.app"
APP_ARTI_BIN="${APP_PATH}/Contents/Resources/Arti/arti"
DIST_DIR="${ROOT_DIR}/dist"
VOLNAME="Tungsten ${VERSION}"
DMG_PATH="${DIST_DIR}/Tungsten-${VERSION}.dmg"

cd "$ROOT_DIR"

bundle_info_value() {
  local app_path="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :${key}" "${app_path}/Contents/Info.plist"
}

verify_bundle_version() {
  local label="$1"
  local app_path="$2"
  local expected_version="$3"
  local expected_build="$4"

  if [[ ! -d "$app_path" ]]; then
    echo "${label} is missing at ${app_path}." >&2
    return 1
  fi

  local actual_version
  local actual_build
  actual_version="$(bundle_info_value "$app_path" CFBundleShortVersionString)"
  actual_build="$(bundle_info_value "$app_path" CFBundleVersion)"

  if [[ "$actual_version" != "$expected_version" || "$actual_build" != "$expected_build" ]]; then
    echo "${label} has version ${actual_version} (${actual_build}), expected ${expected_version} (${expected_build})." >&2
    return 1
  fi
}

verify_dmg_contents() {
  local mount_dir
  mount_dir="$(mktemp -d -t tungsten-dmg-verify)"

  local status=0
  hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$DMG_PATH" >/dev/null || status=$?

  if [[ "$status" -eq 0 ]]; then
    verify_bundle_version "DMG app" "${mount_dir}/Tungsten.app" "$VERSION" "$BUILD_NUMBER" || status=$?
  fi

  hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  rmdir "$mount_dir" 2>/dev/null || true

  return "$status"
}

warn_if_installed_copy_differs() {
  local installed_app="/Applications/Tungsten.app"

  if [[ ! -d "$installed_app" ]]; then
    return
  fi

  local installed_version
  local installed_build
  installed_version="$(bundle_info_value "$installed_app" CFBundleShortVersionString 2>/dev/null || true)"
  installed_build="$(bundle_info_value "$installed_app" CFBundleVersion 2>/dev/null || true)"

  if [[ "$installed_version" != "$VERSION" || "$installed_build" != "$BUILD_NUMBER" ]]; then
    cat <<EOF

Warning: /Applications/Tungsten.app is still ${installed_version:-unknown} (${installed_build:-unknown}).
The packaged DMG contains ${VERSION} (${BUILD_NUMBER}), but Dock/Spotlight may keep opening the installed copy until you replace it.
EOF
  fi
}

echo "Building release app for package..."
rm -rf "$APP_PATH"
TUNGSTEN_VERSION="$VERSION" TUNGSTEN_BUILD_NUMBER="$BUILD_NUMBER" \
  "${ROOT_DIR}/scripts/build-release.sh" -quiet

if [[ ! -x "$APP_ARTI_BIN" ]]; then
  echo "Release build is missing bundled Arti at $APP_ARTI_BIN; rebuilding..."
  rm -rf "$APP_PATH"
  TUNGSTEN_VERSION="$VERSION" TUNGSTEN_BUILD_NUMBER="$BUILD_NUMBER" \
    "${ROOT_DIR}/scripts/build-release.sh" -quiet
fi

if [[ ! -x "$APP_ARTI_BIN" ]]; then
  echo "Cannot package Tungsten without bundled Arti at $APP_ARTI_BIN." >&2
  exit 1
fi

verify_bundle_version "Release app" "$APP_PATH" "$VERSION" "$BUILD_NUMBER"

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

verify_dmg_contents
warn_if_installed_copy_differs

SIZE_HUMAN="$(du -h "$DMG_PATH" | awk '{print $1}')"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

cat <<EOF

Built: $DMG_PATH  (${SIZE_HUMAN}, sha256 ${SHA256})
Verified app: ${VERSION} (${BUILD_NUMBER})

Friends' install steps (ad-hoc signed, arm64 only):
  1. Open the .dmg and drag Tungsten into Applications.
  2. First launch will be blocked by Gatekeeper.
     Open System Settings → Privacy & Security, scroll down, click
     "Open Anyway" next to the Tungsten warning, then confirm.
  3. If their browser stamped the file with a quarantine bit and
     "Open Anyway" still won't appear, they can run:
       xattr -dr com.apple.quarantine /Applications/Tungsten.app
EOF
