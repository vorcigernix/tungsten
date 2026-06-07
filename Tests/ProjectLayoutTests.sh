#!/usr/bin/env bash
set -euo pipefail

project_file="Tungsten/Tungsten.xcodeproj/project.pbxproj"
source_root="Tungsten/Sources/Tungsten"
legacy_source_root="Tungsten/Tungsten"

require_path() {
    local path="$1"
    local description="$2"

    if [[ ! -e "$path" ]]; then
        echo "Missing ${description}: ${path}" >&2
        exit 1
    fi
}

reject_path() {
    local path="$1"
    local description="$2"

    if [[ -e "$path" ]]; then
        echo "Unexpected ${description}: ${path}" >&2
        exit 1
    fi
}

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q -- "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_path "${source_root}/Application/TungstenApp.swift" "app entry point under Sources"
require_path "${source_root}/Application/AppPreferences.swift" "app preferences under Application"
require_path "${source_root}/Browser/Navigation/AddressResolver.swift" "navigation resolver feature folder"
require_path "${source_root}/Browser/History/HistoryStore.swift" "history store feature folder"
require_path "${source_root}/Browser/Chrome/ChromeMetrics.swift" "chrome metrics filename"

reject_path "${legacy_source_root}/Application/TungstenApp.swift" "legacy duplicated app source root"
reject_path "Tungsten/Tungsten.xcodeproj/.xcodesamplecode.plist" "empty Xcode sample metadata"

require_pattern "$project_file" "path = Sources/Tungsten" "filesystem-synchronized source root"
require_pattern "$project_file" "CODE_SIGN_ENTITLEMENTS = Sources/Tungsten/Tungsten.entitlements" "entitlements path under Sources"
require_pattern "$project_file" "SWIFT_OBJC_BRIDGING_HEADER = \"Sources/Tungsten/Tungsten-Bridging-Header.h\"" "bridging header path under Sources"

echo "ProjectLayoutTests passed"
