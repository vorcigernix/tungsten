#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"
APP_VERSION="${TUNGSTEN_VERSION:-0.11}"
BUILD_NUMBER="${TUNGSTEN_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
ARTI_VENDOR_BIN="${ROOT_DIR}/Vendor/Arti/bin/arti"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/Tungsten.app"
APP_ARTI_BIN="${APP_PATH}/Contents/Resources/Arti/arti"

cd "$ROOT_DIR"

if [[ ! -x "$ARTI_VENDOR_BIN" ]]; then
  echo "Arti not found at $ARTI_VENDOR_BIN; running setup-arti.sh..."
  "${ROOT_DIR}/scripts/setup-arti.sh"
fi

xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "$@" \
  build

if [[ ! -x "$APP_ARTI_BIN" ]]; then
  echo "Release build did not embed Arti at $APP_ARTI_BIN." >&2
  echo "Run ./scripts/setup-arti.sh and build again." >&2
  exit 1
fi

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R "$APP_PATH" >/dev/null 2>&1 || true

echo
echo "Built: $APP_PATH"
echo "Version: $APP_VERSION ($BUILD_NUMBER)"
echo "Bundled Arti: $APP_ARTI_BIN"
