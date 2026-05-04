#!/usr/bin/env bash
set -euo pipefail

CEF_CURRENT="${SRCROOT}/../Vendor/CEF/current"
FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [[ ! -d "${CEF_CURRENT}" ]]; then
  echo "Missing CEF runtime at ${CEF_CURRENT}." >&2
  echo "Run ./scripts/setup-cef.sh --arch arm64 from the repository root." >&2
  exit 1
fi

CEF_RUNTIME_CONFIGURATION="${CEF_RUNTIME_CONFIGURATION:-Release}"
FRAMEWORK_SRC="${CEF_CURRENT}/${CEF_RUNTIME_CONFIGURATION}/Chromium Embedded Framework.framework"

HELPER_NAMES=(
  "Tungsten Helper"
  "Tungsten Helper (Alerts)"
  "Tungsten Helper (GPU)"
  "Tungsten Helper (Plugin)"
  "Tungsten Helper (Renderer)"
)

if [[ ! -d "${FRAMEWORK_SRC}" ]]; then
  echo "Missing ${CEF_RUNTIME_CONFIGURATION} Chromium Embedded Framework.framework in ${CEF_CURRENT}." >&2
  exit 1
fi

for helper_name in "${HELPER_NAMES[@]}"; do
  if [[ ! -d "${CEF_CURRENT}/build/${helper_name}.app" ]]; then
    echo "Missing ${helper_name}.app. Run ./scripts/setup-cef.sh --arch arm64 again." >&2
    exit 1
  fi
done

mkdir -p "${FRAMEWORKS_DIR}"

rm -rf "${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework"
rm -rf "${FRAMEWORKS_DIR}"/Tungsten\ Helper*.app

CEF_FRAMEWORK_DST="${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework"
CEF_FRAMEWORK_VERSION_DST="${CEF_FRAMEWORK_DST}/Versions/A"

mkdir -p "${CEF_FRAMEWORK_VERSION_DST}"
ditto "${FRAMEWORK_SRC}/Chromium Embedded Framework" "${CEF_FRAMEWORK_VERSION_DST}/Chromium Embedded Framework"
ditto "${FRAMEWORK_SRC}/Resources" "${CEF_FRAMEWORK_VERSION_DST}/Resources"
ditto "${FRAMEWORK_SRC}/Libraries" "${CEF_FRAMEWORK_VERSION_DST}/Libraries"

ln -sfn A "${CEF_FRAMEWORK_DST}/Versions/Current"
ln -sfn "Versions/Current/Chromium Embedded Framework" "${CEF_FRAMEWORK_DST}/Chromium Embedded Framework"
ln -sfn "Versions/Current/Resources" "${CEF_FRAMEWORK_DST}/Resources"
ln -sfn "Versions/Current/Libraries" "${CEF_FRAMEWORK_DST}/Libraries"

for helper_name in "${HELPER_NAMES[@]}"; do
  ditto "${CEF_CURRENT}/build/${helper_name}.app" "${FRAMEWORKS_DIR}/${helper_name}.app"
done

cat > "${CEF_FRAMEWORK_VERSION_DST}/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Chromium Embedded Framework</string>
  <key>CFBundleIdentifier</key>
  <string>org.chromium.cef.framework</string>
  <key>CFBundleName</key>
  <string>Chromium Embedded Framework</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>147.0.7727.118</string>
  <key>CFBundleVersion</key>
  <string>147.0.7727.118</string>
</dict>
</plist>
PLIST

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --deep --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework"
  for helper_name in "${HELPER_NAMES[@]}"; do
    /usr/bin/codesign --force --deep --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${FRAMEWORKS_DIR}/${helper_name}.app"
  done
fi
