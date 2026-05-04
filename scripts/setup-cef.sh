#!/usr/bin/env bash
set -euo pipefail

CEF_VERSION="147.0.10+gd58e84d+chromium-147.0.7727.118"
CHROMIUM_VERSION="147.0.7727.118"
ARCH="arm64"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/CEF"
DOWNLOAD_DIR="${VENDOR_DIR}/downloads"
BUILD_TYPE="Release"

usage() {
  echo "Usage: $0 [--arch arm64|x64]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "${ARCH}" in
  arm64)
    PLATFORM="macosarm64"
    CMAKE_ARCH="arm64"
    ;;
  x64|x86_64)
    PLATFORM="macosx64"
    CMAKE_ARCH="x86_64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 2
    ;;
esac

ARCHIVE="cef_binary_${CEF_VERSION}_${PLATFORM}.tar.bz2"
URL="https://cef-builds.spotifycdn.com/${ARCHIVE}"
DIST_DIR="${VENDOR_DIR}/cef_binary_${CEF_VERSION}_${PLATFORM}"
CURRENT_LINK="${VENDOR_DIR}/current"
WRAPPER_OUT="${DIST_DIR}/lib/libcef_dll_wrapper.a"
HELPER_BUILD_DIR="${DIST_DIR}/build"
HELPER_STAGING_BINARY="${HELPER_BUILD_DIR}/Tungsten Helper Binary"

mkdir -p "${DOWNLOAD_DIR}" "${DIST_DIR}/lib"

if [[ ! -d "${DIST_DIR}/include" ]]; then
  if [[ ! -f "${DOWNLOAD_DIR}/${ARCHIVE}" ]]; then
    echo "Downloading ${ARCHIVE}"
    curl -fL "${URL}" -o "${DOWNLOAD_DIR}/${ARCHIVE}"
  fi

  echo "Extracting ${ARCHIVE}"
  rm -rf "${DIST_DIR}"
  mkdir -p "${VENDOR_DIR}"
  tar -xjf "${DOWNLOAD_DIR}/${ARCHIVE}" -C "${VENDOR_DIR}"
fi

if [[ ! -f "${WRAPPER_OUT}" ]]; then
  echo "Building libcef_dll_wrapper"
  cmake -S "${DIST_DIR}" -B "${DIST_DIR}/build" -DPROJECT_ARCH="${CMAKE_ARCH}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
  cmake --build "${DIST_DIR}/build" --target libcef_dll_wrapper --config "${BUILD_TYPE}"

  FOUND_WRAPPER="$(find "${DIST_DIR}/build" -name libcef_dll_wrapper.a -print -quit)"
  if [[ -z "${FOUND_WRAPPER}" ]]; then
    echo "libcef_dll_wrapper.a was not produced by the CEF build." >&2
    exit 1
  fi

  mkdir -p "$(dirname "${WRAPPER_OUT}")"
  cp "${FOUND_WRAPPER}" "${WRAPPER_OUT}"
fi

if [[ ! -x "${HELPER_STAGING_BINARY}" || "${ROOT_DIR}/CEFHelper/TungstenCEFHelperMain.mm" -nt "${HELPER_STAGING_BINARY}" || "${WRAPPER_OUT}" -nt "${HELPER_STAGING_BINARY}" ]]; then
  echo "Building Tungsten helper executable"
  mkdir -p "${HELPER_BUILD_DIR}"
  clang++ \
    -std=c++20 \
    -stdlib=libc++ \
    -fobjc-arc \
    -mmacosx-version-min=13.0 \
    -arch "${CMAKE_ARCH}" \
    -I"${DIST_DIR}" \
    -I"${DIST_DIR}/include" \
    -I"${DIST_DIR}/libcef_dll" \
    "${ROOT_DIR}/CEFHelper/TungstenCEFHelperMain.mm" \
    "${WRAPPER_OUT}" \
    -framework AppKit \
    -framework Cocoa \
    -framework Foundation \
    -o "${HELPER_STAGING_BINARY}"
fi

write_helper_app() {
  local helper_name="$1"
  local bundle_suffix="$2"
  local helper_app="${HELPER_BUILD_DIR}/${helper_name}.app"
  local helper_binary="${helper_app}/Contents/MacOS/${helper_name}"
  local bundle_id="dev.tungsten.browser.${bundle_suffix}"

  mkdir -p "${helper_app}/Contents/MacOS" "${helper_app}/Contents/Resources"
  cp "${HELPER_STAGING_BINARY}" "${helper_binary}"
  chmod +x "${helper_binary}"

  cat > "${helper_app}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${helper_name}</string>
  <key>CFBundleExecutable</key>
  <string>${helper_name}</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_id}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${helper_name}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${CHROMIUM_VERSION}</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleVersion</key>
  <string>${CHROMIUM_VERSION}</string>
  <key>LSEnvironment</key>
  <dict>
    <key>MallocNanoZone</key>
    <string>0</string>
  </dict>
  <key>LSFileQuarantineEnabled</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST
}

write_helper_app "Tungsten Helper" "helper"
write_helper_app "Tungsten Helper (Alerts)" "helper.alerts"
write_helper_app "Tungsten Helper (GPU)" "helper.gpu"
write_helper_app "Tungsten Helper (Plugin)" "helper.plugin"
write_helper_app "Tungsten Helper (Renderer)" "helper.renderer"

ln -sfn "$(basename "${DIST_DIR}")" "${CURRENT_LINK}"

cat > "${DIST_DIR}/TungstenCEF.version" <<VERSION
CEF_VERSION=${CEF_VERSION}
CHROMIUM_VERSION=${CHROMIUM_VERSION}
PLATFORM=${PLATFORM}
ARCH=${ARCH}
VERSION

echo "CEF is ready at ${CURRENT_LINK}"
