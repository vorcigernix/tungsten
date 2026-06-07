#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_FILE="$ROOT_DIR/Tungsten/Sources/Tungsten/Browser/BrowserModel.swift"
TAB_FILE="$ROOT_DIR/Tungsten/Sources/Tungsten/Browser/Tabs/BrowserTab.swift"
SPLIT_VIEW_FILE="$ROOT_DIR/Tungsten/Sources/Tungsten/Browser/BrowserSplitView.swift"
CHROME_FILE="$ROOT_DIR/Tungsten/Sources/Tungsten/Browser/Chrome/BrowserChrome.swift"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing $label"
        exit 1
    fi
}

require_pattern "$TAB_FILE" "struct BrowserTab" "BrowserTab model"
require_pattern "$TAB_FILE" "var isPinned" "BrowserTab.isPinned"
require_pattern "$MODEL_FILE" "func createTab\\(" "BrowserModel.createTab"
require_pattern "$MODEL_FILE" "func closeSelectedTab\\(" "BrowserModel.closeSelectedTab"
require_pattern "$MODEL_FILE" "func toggleSelectedTabPin\\(" "BrowserModel.toggleSelectedTabPin"
require_pattern "$MODEL_FILE" "func toggleTabPin\\(" "BrowserModel.toggleTabPin"
require_pattern "$MODEL_FILE" "func clearUnpinnedTabs\\(" "BrowserModel.clearUnpinnedTabs"
require_pattern "$MODEL_FILE" "func reopenLastClosedTab\\(" "BrowserModel.reopenLastClosedTab"
require_pattern "$MODEL_FILE" "closedTabs\\.append" "closed tab snapshot recording"
require_pattern "$CHROME_FILE" "Pin Tab|Unpin Tab" "pin/unpin tab context menu"
require_pattern "$CHROME_FILE" "Close Other Tabs" "close other tabs context menu"
require_pattern "$CHROME_FILE" "TabPrivacyModeFavicon" "combined privacy mode favicon"
require_pattern "$CHROME_FILE" "tab\\.privacyMode" "tab privacy mode read in chrome"
require_pattern "$CHROME_FILE" "Normal tab|Private tab|Tor tab" "privacy mode accessibility labels"
require_pattern "$CHROME_FILE" "173\\.0 / 255\\.0" "microsite lime private tab color"
require_pattern "$CHROME_FILE" "200\\.0 / 255\\.0" "microsite purple tor tab color"

if rg -q "TabPrivacyModeChip|tabModeShortLabel|Text\\(mode\\.tabMode" "$CHROME_FILE"; then
    echo "Tab privacy state should be color coding around the favicon, not a separate visible badge"
    exit 1
fi

echo "BrowserTabStateTests passed"
