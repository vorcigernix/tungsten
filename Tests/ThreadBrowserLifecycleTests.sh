#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"
split_view_file="Tungsten/Tungsten/Browser/BrowserSplitView.swift"
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
require_file "$split_view_file" "BrowserSplitView.swift"

require_pattern "$session_file" "final class BrowserPageSession" "BrowserPageSession class"
require_pattern "$host_file" "final class LivePageSessionHost" "LivePageSessionHost class"
require_pattern "$host_file" "func activate\\(pageTurn: BrowserTurn, isIncognito: Bool, configure: \\(BrowserPageSession\\) -> Void\\)" "LivePageSessionHost.activate(pageTurn:isIncognito:configure:)"
require_pattern "$model_file" "activePageSession" "BrowserModel.activePageSession bridge"
require_pattern "$model_file" "var threads: \\[BrowserThread\\]" "BrowserModel thread state"
require_pattern "$model_file" "selectedThreadID" "BrowserModel selected thread state"
require_pattern "$model_file" "var isGeneratingResponse = false" "BrowserModel response generation state"
require_pattern "$model_file" "pendingResponseID" "BrowserModel pending response token"
require_pattern "$session_file" "controller\\.delegate = observer" "BrowserPageSession controller delegate wiring"
require_pattern "$session_file" "browserDidCloseHandler" "BrowserPageSession browser close handler"
require_pattern "$session_file" "onFaviconURLChange" "BrowserPageSession favicon URL callback"
require_pattern "$session_file" "func pageContentContext\\(\\) async -> PageContentContext\\?" "BrowserPageSession page content context async API"
require_pattern "$session_file" "browserController\\.extractPageContent" "BrowserPageSession page content extraction bridge"
require_pattern "$session_file" "func closeBrowser\\(" "BrowserPageSession closeBrowser forwarding method"
require_pattern "$session_file" "browserController\\.closeBrowser\\(" "BrowserPageSession closeBrowser forwarding call"
require_pattern "$session_file" "func closeBrowserForWindowClose\\(" "BrowserPageSession closeBrowserForWindowClose forwarding method"
require_pattern "$session_file" "browserController\\.closeBrowserForWindowClose\\(" "BrowserPageSession closeBrowserForWindowClose forwarding call"
require_pattern "$host_file" "closingPageSession" "LivePageSessionHost pending window-close session retention"
require_pattern "$host_file" "originalOnClose\\?\\(\\)" "LivePageSessionHost preserves original close callback"
require_pattern "$host_file" "closingPageSession = nil" "LivePageSessionHost releases pending window-close session"
require_pattern "$split_view_file" "ThreadHistoryPopover" "thread history popover"
require_pattern "$split_view_file" "clock\\.arrow\\.circlepath" "thread history toolbar icon"
require_pattern "$split_view_file" "matchesHistorySearch" "thread history search filter"
require_pattern "$split_view_file" "FaviconIcon" "shared favicon rendering view"
require_pattern "$split_view_file" "FaviconLoader\\.shared\\.image" "thread UI favicon loading"
require_pattern "$split_view_file" "turn\\.faviconURLString" "page bubble favicon source"
require_pattern "$split_view_file" "isPageLoading \\? \"xmark\" : \"arrow\\.clockwise\"" "stable reload/stop icon swap"
require_pattern "$split_view_file" "\\.frame\\(width: 28, height: 24\\)" "fixed reload/stop button frame"
require_pattern "$split_view_file" "\\.frame\\(width: 16, height: 16\\)" "fixed reload/stop symbol frame"

if rg -q "typealias BrowserTab = BrowserPageSession" "$model_file"; then
    echo "BrowserModel must not keep BrowserTab as a BrowserPageSession typealias" >&2
    exit 1
fi

if rg -q "Picker\\(\"Thread\"" "$split_view_file"; then
    echo "ThreadHeader must use a history/search popover instead of a thread dropdown picker" >&2
    exit 1
fi

if ! awk '
    /controller\.browserDidCloseHandler =/ { in_handler = 1 }
    in_handler && /self\?\.onBrowserClose\?\(\)/ { saw_forward = 1 }
    in_handler && /return controller/ {
        if (saw_forward) {
            exit 0
        }
        exit 1
    }
    END {
        if (!saw_forward) {
            exit 1
        }
    }
' "$session_file"; then
    echo "BrowserPageSession.browserDidCloseHandler must forward to onBrowserClose?()" >&2
    exit 1
fi

if ! awk '
    /func updateFavicon\(from urls: \[String\]\)/ { in_update_favicon = 1 }
    in_update_favicon && /onFaviconURLChange\?\(candidate\)/ { saw_forward = 1 }
    in_update_favicon && /faviconFetchTask = Task/ {
        if (saw_forward) {
            exit 0
        }
        exit 1
    }
    END {
        if (!saw_forward) {
            exit 1
        }
    }
' "$session_file"; then
    echo "BrowserPageSession.updateFavicon must forward accepted favicon candidates to onFaviconURLChange?(candidate)" >&2
    exit 1
fi

if ! awk '
    /func activate\(pageTurn: BrowserTurn, isIncognito: Bool, configure: \(BrowserPageSession\) -> Void\)/ { in_activate = 1 }
    in_activate && /closeActivePage\(\)/ { saw_close = 1 }
    in_activate && /let session = BrowserPageSession/ {
        if (!saw_close) {
            exit 1
        }
        saw_session = 1
    }
    in_activate && /^    }$/ && saw_session { exit 0 }
    END {
        if (!saw_session) {
            exit 1
        }
    }
' "$host_file"; then
    echo "LivePageSessionHost.activate must close the active page before creating a replacement session" >&2
    exit 1
fi

if ! awk '
    /func closeActivePageForWindowClose\(\)/ { in_close = 1 }
    in_close && /session\.onBrowserClose =/ { saw_handler = 1 }
    in_close && /closingPageSession = nil/ {
        if (!saw_handler) {
            exit 1
        }
        saw_release = 1
    }
    in_close && /^    }$/ && saw_release { exit 0 }
    END {
        if (!saw_release) {
            exit 1
        }
    }
' "$host_file"; then
    echo "LivePageSessionHost.closeActivePageForWindowClose must clear closingPageSession from onBrowserClose" >&2
    exit 1
fi

echo "ThreadBrowserLifecycleTests passed"
