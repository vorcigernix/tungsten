#!/usr/bin/env bash
set -euo pipefail

CEF_CURRENT="${SRCROOT}/../Vendor/CEF/current"
ARTI_VENDOR_BIN="${SRCROOT}/../Vendor/Arti/bin/arti"
FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
ARTI_RESOURCE_BIN="${RESOURCES_DIR}/Arti/arti"
APP_INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH:-${WRAPPER_NAME}/Contents/Info.plist}"

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

rm -rf "${RESOURCES_DIR}/Arti"
if [[ -x "${ARTI_VENDOR_BIN}" ]]; then
  mkdir -p "${RESOURCES_DIR}/Arti"
  ditto "${ARTI_VENDOR_BIN}" "${ARTI_RESOURCE_BIN}"
  chmod 755 "${ARTI_RESOURCE_BIN}"
else
  echo "warning: Arti binary not found at ${ARTI_VENDOR_BIN}; Tor tabs will require an external Arti path or SOCKS proxy." >&2
fi

if [[ -f "${RESOURCES_DIR}/AppIcon.icns" && -f "${APP_INFO_PLIST}" ]]; then
  ICON_BUILD_NUMBER="${CURRENT_PROJECT_VERSION:-local}"
  ICON_RESOURCE_BASENAME="TungstenPrivacyShield-${ICON_BUILD_NUMBER}"
  ICON_RESOURCE_BIN="${RESOURCES_DIR}/${ICON_RESOURCE_BASENAME}.icns"

  rm -f "${RESOURCES_DIR}"/TungstenPrivacyShield-*.icns
  ditto "${RESOURCES_DIR}/AppIcon.icns" "${ICON_RESOURCE_BIN}"
  /usr/bin/plutil -replace CFBundleIconFile -string "${ICON_RESOURCE_BASENAME}" "${APP_INFO_PLIST}"
  /usr/bin/plutil -remove CFBundleIconName "${APP_INFO_PLIST}" 2>/dev/null || true
else
  echo "warning: AppIcon.icns or Info.plist was not available for versioned production icon metadata." >&2
fi

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
  if [[ -x "${ARTI_RESOURCE_BIN}" ]]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${ARTI_RESOURCE_BIN}"
  fi
fi
