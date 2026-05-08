#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"
window_root_file="Tungsten/Tungsten/Browser/BrowserWindowRoot.swift"
host_file="Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift"
controller_header="Tungsten/Tungsten/CEF/TungstenBrowserController.h"
bridge_file="Tungsten/Tungsten/CEF/TungstenCEFBridge.mm"

if ! rg -q -- "- \\(void\\)closeBrowser;" "$controller_header"; then
    echo "TungstenBrowserController must expose closeBrowser so BrowserModel can close CEF before dropping a tab." >&2
    exit 1
fi

if ! rg -q -- "- \\(void\\)closeBrowserForWindowClose;" "$controller_header"; then
    echo "TungstenBrowserController must expose closeBrowserForWindowClose so top-level window close can use CEF's non-forced close sequence." >&2
    exit 1
fi

if ! rg -q -- "browserDidCloseHandler" "$controller_header"; then
    echo "TungstenBrowserController must expose a browserDidCloseHandler so window close can wait for CEF teardown." >&2
    exit 1
fi

if ! awk '
    /func closeActivePage\(\)/ { in_close = 1; found = 1 }
    in_close && /activePageSession\?\.closeBrowser\(\)/ { saw_close = 1 }
    in_close && /activePageSession = nil/ { saw_clear = 1 }
    in_close && /^    }$/ { exit (saw_close && saw_clear) ? 0 : 1 }
    END { if (!found) exit 1 }
' "$host_file"; then
    echo "LivePageSessionHost.closeActivePage must call closeBrowser() before clearing the active CEF page session." >&2
    exit 1
fi

if ! awk '
    /func closeBrowsersForWindowClose\(completion:/ { in_close = 1; found = 1 }
    in_close && /livePageHost\.closeActivePageForWindowClose\(\)/ { saw_close = 1 }
    in_close && /completion\(\)/ { saw_completion = 1 }
    in_close && /^    }$/ { exit saw_close ? 0 : 1 }
    END { if (!found || !saw_completion) exit 1 }
' "$model_file"; then
    echo "BrowserModel must expose a window-close cleanup path that asks the live page host to perform CEF's non-forced close and completes after teardown." >&2
    exit 1
fi

if ! awk '
    /func closeActivePageForWindowClose\(\)/ { in_close = 1; found = 1 }
    in_close && /session\.closeBrowserForWindowClose\(\)/ { saw_close = 1 }
    in_close && /^    }$/ { exit saw_close ? 0 : 1 }
    END { if (!found) exit 1 }
' "$host_file"; then
    echo "LivePageSessionHost.closeActivePageForWindowClose must forward to BrowserPageSession.closeBrowserForWindowClose()." >&2
    exit 1
fi

if ! rg -q -- "WindowCloseObserver" "$window_root_file" ||
   ! rg -q -- "windowShouldClose" "$window_root_file" ||
   ! rg -q -- "return false" "$window_root_file" ||
   ! rg -q -- "closeBrowsersForWindowClose[[:space:]]*\\{" "$window_root_file"; then
    echo "BrowserWindowRoot must intercept NSWindow close, cancel immediate teardown, and close after CEF browsers finish." >&2
    exit 1
fi

if ! awk '
    /- \(void\)cefBrowserDidClose \{/ { in_close = 1; found = 1 }
    in_close && /browserDidCloseHandler/ { saw_handler = 1 }
    in_close && /^}/ { exit saw_handler ? 0 : 1 }
    END { if (!found) exit 1 }
' "$bridge_file"; then
    echo "TungstenBrowserController must invoke browserDidCloseHandler from cefBrowserDidClose." >&2
    exit 1
fi

if ! awk '
    /- \(void\)closeBrowserForWindowClose \{/ { in_window_close = 1; found = 1 }
    in_window_close && /closeBrowserWithForce:NO/ { saw_non_forced_close = 1 }
    in_window_close && /^}/ { exit saw_non_forced_close ? 0 : 1 }
    END { if (!found) exit 1 }
' "$bridge_file"; then
    echo "TungstenBrowserController.closeBrowserForWindowClose must call CEF's non-forced CloseBrowser(false) path." >&2
    exit 1
fi

if ! awk '
    /bool DoClose\(CefRefPtr<CefBrowser> browser\) override/ { in_do_close = 1 }
    in_do_close && /return true;/ { saw_true = 1 }
    in_do_close && /^    }$/ { exit saw_true ? 0 : 1 }
' "$bridge_file"; then
    echo "TungstenBrowserClient::DoClose must return true so CEF does not send default close events to the SwiftUI window." >&2
    exit 1
fi

echo "CEFBrowserLifecycleTests passed"
