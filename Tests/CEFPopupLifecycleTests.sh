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

require_pattern "$controller_header" "TungstenPopupOpenHandler" "popup-open callback type"
require_pattern "$controller_header" "popupOpenHandler" "popup-open callback property"

require_pattern "$bridge_file" "OnBeforePopup" "CEF popup interception"
require_pattern "$bridge_file" "popupOpenHandler" "CEF popup forwarding to Swift"
require_pattern "$bridge_file" "cef\\.popup\\.openTab" "popup-open performance logging"

if ! awk '
    /bool OnBeforePopup\(CefRefPtr<CefBrowser> browser,/ { in_popup = 1; found = 1 }
    in_popup && /handler\(urlString\)/ { saw_handler = 1 }
    in_popup && /return true;/ { saw_cancel = 1 }
    in_popup && /^    }$/ { exit (saw_handler && saw_cancel) ? 0 : 1 }
    END { if (!found) exit 1 }
' "$bridge_file"; then
    echo "TungstenBrowserClient::OnBeforePopup must forward the target URL to Swift and return true to cancel native CEF popup windows." >&2
    exit 1
fi

if ! awk '
    /void OnAfterCreated\(CefRefPtr<CefBrowser> browser\) override/ { in_after = 1; found = 1 }
    in_after && /browser_ && !browser_->IsSame\(browser\)/ { saw_popup_guard = 1 }
    in_after && /browser_ = browser/ { saw_main_assignment = 1 }
    in_after && /^    }$/ { exit (saw_popup_guard && saw_main_assignment) ? 0 : 1 }
    END { if (!found) exit 1 }
' "$bridge_file"; then
    echo "TungstenBrowserClient::OnAfterCreated must not let an unexpected popup replace the tracked embedded browser." >&2
    exit 1
fi

if ! awk '
    /bool DoClose\(CefRefPtr<CefBrowser> browser\) override/ { in_close = 1; found = 1 }
    in_close && /browser_ && !browser_->IsSame\(browser\)/ { saw_popup_guard = 1 }
    in_close && /return false;/ { saw_native_close = 1 }
    in_close && /return true;/ { saw_embedded_close = 1 }
    in_close && /^    }$/ { exit (saw_popup_guard && saw_native_close && saw_embedded_close) ? 0 : 1 }
    END { if (!found) exit 1 }
' "$bridge_file"; then
    echo "TungstenBrowserClient::DoClose must reserve custom child-view teardown for the tracked embedded browser and let unexpected native popups close normally." >&2
    exit 1
fi

if ! awk '
    /void OnBeforeClose\(CefRefPtr<CefBrowser> browser\) override/ { in_close = 1; found = 1 }
    in_close && /const bool isTrackedBrowser/ { saw_tracking = 1 }
    in_close && /if \(!isTrackedBrowser\)/ { saw_popup_guard = 1 }
    in_close && /cefBrowserDidClose/ { saw_main_callback = 1 }
    in_close && /^    }$/ { exit (saw_tracking && saw_popup_guard && saw_main_callback) ? 0 : 1 }
    END { if (!found) exit 1 }
' "$bridge_file"; then
    echo "TungstenBrowserClient::OnBeforeClose must invoke cefBrowserDidClose only for the tracked embedded browser." >&2
    exit 1
fi

require_pattern "$page_session_file" "configurePopupOpening" "page session popup callback configuration"
require_pattern "$page_session_file" "popupOpenHandler" "page session forwards CEF popup URL"

require_pattern "$model_file" "openPopupTab" "BrowserModel popup tab action"
require_pattern "$model_file" "privacyMode: pageSession\\.privacyMode" "popup tabs preserve the source tab privacy mode"
require_pattern "$model_file" "configurePopupOpening" "BrowserModel wires popup callback"

echo "CEFPopupLifecycleTests passed"
