#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Sources/Tungsten/Browser/BrowserModel.swift"
window_root_file="Tungsten/Sources/Tungsten/Browser/BrowserWindowRoot.swift"
host_file="Tungsten/Sources/Tungsten/Browser/Threads/LivePageSessionHost.swift"
controller_header="Tungsten/Sources/Tungsten/CEF/TungstenBrowserController.h"
cef_header="Tungsten/Sources/Tungsten/CEF/TungstenCEFApp.h"
bridge_file="Tungsten/Sources/Tungsten/CEF/TungstenCEFBridge.mm"
app_file="Tungsten/Sources/Tungsten/Application/TungstenApp.swift"

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

if ! rg -q -- "extractPageContentWithCompletion" "$controller_header" ||
   ! rg -q -- "TungstenPageContentCompletion" "$controller_header"; then
    echo "TungstenBrowserController must expose a page-content extraction callback for local AI page questions." >&2
    exit 1
fi

if ! rg -q -- "TUNGSTEN_PAGE_TEXT" "$bridge_file" ||
   ! rg -q -- "document\\.body&&document\\.body\\.innerText" "$bridge_file" ||
   ! rg -q -- "window\\.getSelection" "$bridge_file"; then
    echo "CEF bridge must extract selected text/body text from the active page for local AI context." >&2
    exit 1
fi

if rg -q -- "TUNGSTEN_LOCAL_AI|LanguageModel\\.availability|LanguageModel\\.create|downloadprogress|Gemini Nano|answerWithGoogleLocalAI|checkGoogleLocalAIAvailability|prepareGoogleLocalAI" "$controller_header" "$bridge_file"; then
    echo "CEF bridge must not own Gemma 4 Local inference or keep Gemini Nano Prompt API remnants." >&2
    exit 1
fi

if rg -q -- "TUNGSTEN_BG|bg-probe|didUpdatePageBackgroundColorString|pageBackgroundColor" "$controller_header" "$bridge_file" "$model_file"; then
    echo "Obsolete CEF page background probing must stay removed." >&2
    exit 1
fi

if ! rg -q -- "- \\(void\\)prewarmCEF;" "$cef_header"; then
    echo "TungstenCEFApp must expose prewarmCEF so app/window startup can pay CEF initialization before the first visible page navigation." >&2
    exit 1
fi

if ! rg -q -- "prewarmCEF\\(\\)" "$app_file" "$window_root_file"; then
    echo "App/window startup must call TungstenCEFApp.prewarmCEF() before restored tabs trigger visible CEF page creation." >&2
    exit 1
fi

if ! rg -q -- "cef\\.prewarm\\.start|cef\\.prewarm\\.end|cef\\.prewarm\\.skipped" "$bridge_file"; then
    echo "CEF prewarm must be performance logged so traces show whether initialization was paid before browser creation." >&2
    exit 1
fi

if ! rg -q -- "TUNGSTEN_PERF_MARK" "$bridge_file" ||
   ! rg -q -- "DOMContentLoaded" "$bridge_file" ||
   ! rg -q -- "PerformanceObserver" "$bridge_file" ||
   ! rg -q -- "first-contentful-paint" "$bridge_file" ||
   ! rg -q -- "cef\\.renderer\\.mark" "$bridge_file"; then
    echo "CEF bridge must inject renderer performance markers for DOMContentLoaded and first paint/contentful paint." >&2
    exit 1
fi

if ! rg -q -- "kCFRunLoopBeforeSources[[:space:]]*\\|[[:space:]]*kCFRunLoopBeforeWaiting" "$bridge_file" ||
   ! rg -q -- "CefRunLoopPumpCallback" "$bridge_file"; then
    echo "CEF message pump must run before source/event handling as well as before idle so Chromium is not starved during live scrolling." >&2
    exit 1
fi

if ! rg -q -- "cef\\.messagePump\\.workSlow" "$bridge_file"; then
    echo "CEF message pump must log slow work iterations so scroll jank traces expose main-thread CEF stalls." >&2
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
