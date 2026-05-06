#!/usr/bin/env bash
set -euo pipefail

model_file="Landmarks/Landmarks/Browser/BrowserModel.swift"
controller_header="Landmarks/Landmarks/CEF/TungstenBrowserController.h"
bridge_file="Landmarks/Landmarks/CEF/TungstenCEFBridge.mm"

if ! rg -q -- "- \\(void\\)closeBrowser;" "$controller_header"; then
    echo "TungstenBrowserController must expose closeBrowser so BrowserModel can close CEF before dropping a tab." >&2
    exit 1
fi

if ! awk '
    /func close\(_ tab: BrowserTab\)/ { in_close = 1 }
    in_close && /tabs\.remove\(at:/ && !saw_close { exit 1 }
    in_close && /tab\.closeBrowser\(\)/ { saw_close = 1 }
    in_close && /^    }$/ { exit saw_close ? 0 : 1 }
' "$model_file"; then
    echo "BrowserModel.close must call tab.closeBrowser() before removing non-last tabs." >&2
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
