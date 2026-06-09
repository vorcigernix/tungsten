#!/usr/bin/env bash
set -euo pipefail

host_file="Tungsten/Sources/Tungsten/Browser/Threads/LivePageSessionHost.swift"
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

require_pattern "$host_file" "maximumCachedPageSessions[[:space:]]*=[[:space:]]*10" "10-session warm tab cache limit"
require_pattern "$host_file" "cachedPageSessions: \\[BrowserTab\\.ID: BrowserPageSession\\]" "cached page-session dictionary"
require_pattern "$host_file" "recentTabIDs: \\[BrowserTab\\.ID\\]" "page-session LRU recency list"
require_pattern "$host_file" "cachedPageSessions\\[tab\\.id\\]" "activation reuses an existing cached page session"
require_pattern "$host_file" "touchCachedPageSession\\(tabID:" "activation updates cache recency"
require_pattern "$host_file" "evictStalePageSessionsIfNeeded" "stale cached page-session eviction"
require_pattern "$host_file" "closePage\\(tabID:" "single-tab page-session close API"
require_pattern "$host_file" "closePages\\(tabIDs:" "multi-tab page-session close API"
require_pattern "$host_file" "closeCachedPagesForWindowClose" "window close drains cached page sessions"

if awk '
    /func activate\(/ { in_activate = 1 }
    in_activate && /closeActivePage\(\)/ { found_close_before_create = 1 }
    in_activate && /let session = BrowserPageSession/ { saw_create = 1 }
    in_activate && /^    }$/ && saw_create { exit found_close_before_create ? 0 : 1 }
    END {
        if (!saw_create) {
            exit 1
        }
    }
' "$host_file"; then
    echo "LivePageSessionHost.activate must not close the previous active page before creating or reusing a cached tab session." >&2
    exit 1
fi

if ! awk '
    /func close\(_ tab: BrowserTab\)/ { in_close = 1; found = 1 }
    in_close && /livePageHost\.closePage\(tabID: tab\.id\)/ { saw_close_page = 1 }
    in_close && /^    }$/ { exit saw_close_page ? 0 : 1 }
    END { if (!found) exit 1 }
' "$model_file"; then
    echo "BrowserModel.close must close the cached page session for the removed tab, selected or not." >&2
    exit 1
fi

if ! awk '
    /func closeOtherTabs\(keeping tab: BrowserTab\)/ { in_close = 1; found = 1 }
    in_close && /livePageHost\.closePages\(tabIDs: removedTabs\.map\(\\.id\)\)/ { saw_close_pages = 1 }
    in_close && /^    }$/ { exit saw_close_pages ? 0 : 1 }
    END { if (!found) exit 1 }
' "$model_file"; then
    echo "BrowserModel.closeOtherTabs must close cached page sessions for removed tabs." >&2
    exit 1
fi

if ! awk '
    /func clearUnpinnedTabs\(\)/ { in_clear = 1; found = 1 }
    in_clear && /livePageHost\.closePages\(tabIDs: removedTabs\.map\(\\.id\)\)/ { saw_close_pages = 1 }
    in_clear && /^    }$/ { exit saw_close_pages ? 0 : 1 }
    END { if (!found) exit 1 }
' "$model_file"; then
    echo "BrowserModel.clearUnpinnedTabs must close cached page sessions for removed unpinned tabs." >&2
    exit 1
fi

if ! awk '
    /func closeBrowsersForWindowClose\(completion:/ { in_close = 1; found = 1 }
    in_close && /livePageHost\.closeCachedPagesForWindowClose\(\)/ { saw_close_cache = 1 }
    in_close && /^    }$/ { exit saw_close_cache ? 0 : 1 }
    END { if (!found) exit 1 }
' "$model_file"; then
    echo "BrowserModel.closeBrowsersForWindowClose must drain all cached page sessions on window close." >&2
    exit 1
fi

echo "LivePageSessionCacheTests passed"
