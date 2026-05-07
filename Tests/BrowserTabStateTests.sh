#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_FILE="$ROOT_DIR/Tungsten/Tungsten/Browser/BrowserModel.swift"
SPLIT_VIEW_FILE="$ROOT_DIR/Tungsten/Tungsten/Browser/BrowserSplitView.swift"
CLOSED_TAB_FILE="$ROOT_DIR/Tungsten/Tungsten/Browser/ClosedTab.swift"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing $label"
        exit 1
    fi
}

require_pattern "$MODEL_FILE" "var isPinned" "BrowserTab.isPinned"
require_pattern "$MODEL_FILE" "func toggleSelectedTabPin\\(" "BrowserModel.toggleSelectedTabPin"
require_pattern "$MODEL_FILE" "func togglePin\\(" "BrowserModel.togglePin"
require_pattern "$MODEL_FILE" "func clearUnpinnedTabs\\(" "BrowserModel.clearUnpinnedTabs"
require_pattern "$SPLIT_VIEW_FILE" "Pin Tab|Unpin Tab" "pin/unpin tab context menu"
require_pattern "$SPLIT_VIEW_FILE" "Clear Unpinned Tabs" "clear unpinned tabs UI action"

if [[ ! -f "$CLOSED_TAB_FILE" ]]; then
    echo "Missing ClosedTab"
    exit 1
fi

require_pattern "$MODEL_FILE" "func reopenLastClosedTab\\(" "BrowserModel.reopenLastClosedTab"
require_pattern "$MODEL_FILE" "closedTabs\\.append" "closed tab snapshot recording"
require_pattern "$MODEL_FILE" "ClosedTab\\(" "ClosedTab snapshot construction"

echo "BrowserTabStateTests passed"
