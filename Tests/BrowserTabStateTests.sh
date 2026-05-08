#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_FILE="$ROOT_DIR/Tungsten/Tungsten/Browser/BrowserModel.swift"
THREAD_FILE="$ROOT_DIR/Tungsten/Tungsten/Browser/Threads/BrowserThread.swift"
SPLIT_VIEW_FILE="$ROOT_DIR/Tungsten/Tungsten/Browser/BrowserSplitView.swift"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing $label"
        exit 1
    fi
}

require_pattern "$THREAD_FILE" "var isPinned" "BrowserThread.isPinned"
require_pattern "$MODEL_FILE" "func toggleSelectedThreadPin\\(" "BrowserModel.toggleSelectedThreadPin"
require_pattern "$MODEL_FILE" "func toggleThreadPin\\(" "BrowserModel.toggleThreadPin"
require_pattern "$MODEL_FILE" "func clearUnpinnedThreads\\(" "BrowserModel.clearUnpinnedThreads"
require_pattern "$MODEL_FILE" "func toggleSelectedTabPin\\(" "BrowserModel.toggleSelectedTabPin"
require_pattern "$MODEL_FILE" "func clearUnpinnedTabs\\(" "BrowserModel.clearUnpinnedTabs"
require_pattern "$SPLIT_VIEW_FILE" "Pin Thread|Unpin Thread" "pin/unpin thread context menu"
require_pattern "$SPLIT_VIEW_FILE" "Clear Unpinned Threads" "clear unpinned threads UI action"

require_pattern "$MODEL_FILE" "func reopenLastClosedThread\\(" "BrowserModel.reopenLastClosedThread"
require_pattern "$MODEL_FILE" "func reopenLastClosedTab\\(" "BrowserModel.reopenLastClosedTab"
require_pattern "$MODEL_FILE" "closedThreads\\.append" "closed thread snapshot recording"

echo "BrowserTabStateTests passed"
