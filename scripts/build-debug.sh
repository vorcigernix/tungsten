#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"

cd "$ROOT_DIR"

xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "$@" \
  build

echo
echo "Built: $DERIVED_DATA/Build/Products/Debug/Tungsten.app"
