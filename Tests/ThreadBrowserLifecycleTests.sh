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
require_pattern "$session_file" "controller\\.delegate = observer" "BrowserPageSession controller delegate wiring"
require_pattern "$session_file" "browserDidCloseHandler" "BrowserPageSession browser close handler"
require_pattern "$session_file" "onFaviconURLChange" "BrowserPageSession favicon URL callback"
require_pattern "$session_file" "func closeBrowser\\(" "BrowserPageSession closeBrowser forwarding method"
require_pattern "$session_file" "browserController\\.closeBrowser\\(" "BrowserPageSession closeBrowser forwarding call"
require_pattern "$session_file" "func closeBrowserForWindowClose\\(" "BrowserPageSession closeBrowserForWindowClose forwarding method"
require_pattern "$session_file" "browserController\\.closeBrowserForWindowClose\\(" "BrowserPageSession closeBrowserForWindowClose forwarding call"
require_pattern "$host_file" "closingPageSession" "LivePageSessionHost pending window-close session retention"
require_pattern "$host_file" "originalOnClose\\?\\(\\)" "LivePageSessionHost preserves original close callback"
require_pattern "$host_file" "closingPageSession = nil" "LivePageSessionHost releases pending window-close session"

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
