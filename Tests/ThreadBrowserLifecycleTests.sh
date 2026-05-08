#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"
session_file="Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift"
host_file="Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift"

require_file() {
    local file="$1"
    local label="$2"

    if [[ ! -f "$file" ]]; then
        echo "Missing $label" >&2
        exit 1
    fi
}

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing $label" >&2
        exit 1
    fi
}

require_file "$session_file" "BrowserPageSession.swift"
require_file "$host_file" "LivePageSessionHost.swift"

require_pattern "$session_file" "final class BrowserPageSession" "BrowserPageSession class"
require_pattern "$host_file" "final class LivePageSessionHost" "LivePageSessionHost class"
require_pattern "$host_file" "func activate\\(pageTurn: BrowserTurn, isIncognito: Bool, configure: \\(BrowserPageSession\\) -> Void\\)" "LivePageSessionHost.activate(pageTurn:isIncognito:configure:)"
require_pattern "$model_file" "activePageSession" "BrowserModel.activePageSession bridge"

echo "ThreadBrowserLifecycleTests passed"
