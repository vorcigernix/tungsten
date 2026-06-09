#!/usr/bin/env bash
set -euo pipefail

bridge_file="Tungsten/Sources/Tungsten/CEF/TungstenCEFBridge.mm"
controller_header="Tungsten/Sources/Tungsten/CEF/TungstenBrowserController.h"
page_session_file="Tungsten/Sources/Tungsten/Browser/Threads/BrowserPageSession.swift"
model_file="Tungsten/Sources/Tungsten/Browser/BrowserModel.swift"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_pattern "$controller_header" "TungstenContextMenuSearchHandler" "context-menu search callback type"
require_pattern "$controller_header" "contextMenuSearchHandler" "context-menu search callback property"
require_pattern "$controller_header" "contextMenuSearchEngineName" "context-menu search engine label property"

require_pattern "$bridge_file" "cef_context_menu_handler\\.h" "CEF context-menu handler include"
require_pattern "$bridge_file" "public CefContextMenuHandler" "CEF client context-menu inheritance"
require_pattern "$bridge_file" "GetContextMenuHandler\\(\\)" "CEF context-menu handler provider"
require_pattern "$bridge_file" "kTungstenSearchSelectionCommandID" "custom context-menu command id"
require_pattern "$bridge_file" "MENU_ID_USER_FIRST" "CEF user command id range"
require_pattern "$bridge_file" "GetSelectionText\\(\\)" "selected text extraction from CEF context params"
require_pattern "$bridge_file" "Search .* for" "search menu item label"
require_pattern "$bridge_file" "OnContextMenuCommand" "context-menu command handling"
require_pattern "$bridge_file" "contextMenuSearchHandler" "CEF command forwards selected text to Swift"

require_pattern "$page_session_file" "configureContextMenuSearch" "page session context-menu configuration"
require_pattern "$page_session_file" "contextMenuSearchEngineName" "page session configures menu label engine"
require_pattern "$page_session_file" "contextMenuSearchHandler" "page session forwards search command"

require_pattern "$model_file" "openContextMenuSearch" "BrowserModel context-menu search action"
require_pattern "$model_file" "appPreferences\\.searchEngine\\.searchURL\\(for:" "context-menu search uses configured search engine"
require_pattern "$model_file" "createTab\\(urlString: searchURL" "context-menu search opens a new selected tab"
require_pattern "$model_file" "configureContextMenuSearch" "BrowserModel wires active page callback"

echo "ContextMenuSearchTests passed"
