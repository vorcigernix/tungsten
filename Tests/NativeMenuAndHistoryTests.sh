#!/usr/bin/env bash
set -euo pipefail

app_file="Tungsten/Tungsten/TungstenApp.swift"
context_file="Tungsten/Tungsten/Browser/BrowserCommandContext.swift"
window_root_file="Tungsten/Tungsten/Browser/BrowserWindowRoot.swift"
history_file="Tungsten/Tungsten/Browser/HistoryView.swift"
split_view_file="Tungsten/Tungsten/Browser/BrowserSplitView.swift"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_pattern "$context_file" "FocusedValueKey" "focused browser command context key"
require_pattern "$window_root_file" "focusedSceneValue\\(\\\\\\.browserCommandContext" "focused browser command context installation"

require_pattern "$app_file" "CommandGroup\\(replacing: \\.newItem\\)" "native File menu new-item replacement"
require_pattern "$app_file" "Button\\(\"New Tab\"" "File menu New Tab command"
require_pattern "$app_file" "Button\\(\"New Incognito Tab\"" "File menu New Incognito Tab command"
require_pattern "$app_file" "Button\\(\"New Tor Tab\"" "File menu New Tor Tab command"
require_pattern "$app_file" "Button\\(\"New Window\"" "File menu New Window command"
require_pattern "$app_file" "Button\\(\"New Private Window\"" "File menu New Private Window command"
require_pattern "$app_file" "createTorTab" "File menu dispatches Tor tab creation"

require_pattern "$history_file" "let close: \\(\\) -> Void" "History close action"
require_pattern "$history_file" "Button\\(\"Close\"" "History close button"
require_pattern "$history_file" "keyboardShortcut\\(\\.escape" "History escape shortcut"
require_pattern "$split_view_file" "close: \\{" "History sheet close wiring"
require_pattern "$split_view_file" "browserModel\\.closeHistory\\(\\)" "History close action dispatch"

echo "NativeMenuAndHistoryTests passed"
