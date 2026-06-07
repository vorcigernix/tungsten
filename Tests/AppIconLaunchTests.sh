#!/usr/bin/env bash
set -euo pipefail

app_file="Tungsten/Sources/Tungsten/Application/TungstenApp.swift"
icon_manifest="Tungsten/Sources/Tungsten/AppIcon.icon/icon.json"
project_file="Tungsten/Tungsten.xcodeproj/project.pbxproj"
copy_runtime_script="scripts/copy-cef-runtime.sh"
build_release_script="scripts/build-release.sh"
package_release_script="scripts/package-release.sh"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

if rg -q "applicationIconImage|AppIcon.*icns|NSImage\\(contentsOf:" "$app_file"; then
    echo "The app must not replace the Dock icon at runtime; use the bundle AppIcon to avoid launch-time icon flicker." >&2
    exit 1
fi

require_pattern "$icon_manifest" "tungsten-privacy-shield\\.svg" "current Tungsten shield icon source"
require_pattern "$project_file" "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" "AppIcon asset catalog build setting"
require_pattern "$copy_runtime_script" "TungstenPrivacyShield" "versioned production icon resource"
require_pattern "$copy_runtime_script" "CFBundleIconFile" "production Info.plist icon resource override"
require_pattern "$copy_runtime_script" "CFBundleIconName" "production asset catalog icon name removal"
require_pattern "$build_release_script" "MARKETING_VERSION" "release marketing version override"
require_pattern "$build_release_script" "CURRENT_PROJECT_VERSION" "release build number override"
require_pattern "$build_release_script" "lsregister" "release LaunchServices refresh"
require_pattern "$package_release_script" "TUNGSTEN_BUILD_NUMBER" "package build number propagation"
require_pattern "$package_release_script" "scripts/build-release\\.sh" "package release rebuild"
require_pattern "$package_release_script" 'rm -rf "\$APP_PATH"' "stale release app removal before package builds"
require_pattern "$package_release_script" "CFBundleShortVersionString" "packaged app version verification"
require_pattern "$package_release_script" "CFBundleVersion" "packaged app build verification"
require_pattern "$package_release_script" "hdiutil attach" "DMG content verification mount"
require_pattern "$package_release_script" "hdiutil detach" "DMG content verification unmount"
require_pattern "$package_release_script" "warn_if_installed_copy_differs" "installed app drift warning"

if rg -q 'if \[\[ ! -d "\$APP_PATH" \]\]' "$package_release_script"; then
    echo "package-release must rebuild production apps instead of reusing stale bundles with cached icons." >&2
    exit 1
fi

echo "AppIconLaunchTests passed"
