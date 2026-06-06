#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"
split_view_file="Tungsten/Tungsten/Browser/BrowserSplitView.swift"
detail_view_file="Tungsten/Tungsten/Browser/BrowserDetailView.swift"
app_file="Tungsten/Tungsten/TungstenApp.swift"
session_file="Tungsten/Tungsten/Browser/Threads/BrowserPageSession.swift"
host_file="Tungsten/Tungsten/Browser/Threads/LivePageSessionHost.swift"
tab_file="Tungsten/Tungsten/Browser/Tabs/BrowserTab.swift"
tab_store_file="Tungsten/Tungsten/Browser/Tabs/BrowserTabStore.swift"
settings_file="Tungsten/Tungsten/Settings/GeneralSettingsView.swift"
preferences_file="Tungsten/Tungsten/AppPreferences.swift"
input_file="Tungsten/Tungsten/Browser/Threads/BrowserInputClassifier.swift"

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
require_file "$detail_view_file" "BrowserDetailView.swift"
require_file "$tab_file" "BrowserTab.swift"
require_file "$tab_store_file" "BrowserTabStore.swift"

require_pattern "$session_file" "final class BrowserPageSession" "BrowserPageSession class"
require_pattern "$session_file" "let tabID: BrowserTab\\.ID" "BrowserPageSession tab identity"
require_pattern "$session_file" "controller\\.delegate = observer" "BrowserPageSession controller delegate wiring"
require_pattern "$session_file" "browserDidCloseHandler" "BrowserPageSession browser close handler"
require_pattern "$session_file" "onFaviconURLChange" "BrowserPageSession favicon URL callback"
require_pattern "$session_file" "func closeBrowser\\(" "BrowserPageSession closeBrowser forwarding method"
require_pattern "$session_file" "browserController\\.closeBrowser\\(" "BrowserPageSession closeBrowser forwarding call"
require_pattern "$session_file" "func closeBrowserForWindowClose\\(" "BrowserPageSession closeBrowserForWindowClose forwarding method"
require_pattern "$session_file" "browserController\\.closeBrowserForWindowClose\\(" "BrowserPageSession closeBrowserForWindowClose forwarding call"

require_pattern "$host_file" "final class LivePageSessionHost" "LivePageSessionHost class"
require_pattern "$host_file" "func activate\\(tab: BrowserTab, isIncognito: Bool, configure: \\(BrowserPageSession\\) -> Void\\)" "LivePageSessionHost.activate(tab:isIncognito:configure:)"
require_pattern "$host_file" "activePageSession\\?\\.tabID == tab\\.id" "LivePageSessionHost selected-tab guard"
require_pattern "$host_file" "closeActivePage\\(\\)" "LivePageSessionHost closes active CEF session before replacement"
require_pattern "$host_file" "closingPageSession" "LivePageSessionHost pending window-close session retention"
require_pattern "$host_file" "originalOnClose\\?\\(\\)" "LivePageSessionHost preserves original close callback"
require_pattern "$host_file" "closingPageSession = nil" "LivePageSessionHost releases pending window-close session"

require_pattern "$model_file" "var tabs: \\[BrowserTab\\]" "BrowserModel tab state"
require_pattern "$model_file" "selectedTabID" "BrowserModel selected tab state"
require_pattern "$model_file" "activePageSession" "BrowserModel.activePageSession bridge"
require_pattern "$model_file" "func createTab\\(" "BrowserModel.createTab"
require_pattern "$model_file" "func submitAddressBar\\(" "BrowserModel address submission"
require_pattern "$model_file" "navigateSelectedTab\\(to:" "BrowserModel navigates current tab"
require_pattern "$model_file" "livePageHost\\.activate\\(" "BrowserModel activates selected tab through live page host"
require_pattern "$model_file" "tabStore\\.save\\(tabs: tabs, selectedTabID: selectedTabID\\)" "BrowserModel persists tab snapshot"

require_pattern "$split_view_file" "SafariLiquidChrome" "transparent Safari-style liquid chrome overlay"
require_pattern "$split_view_file" "SafariChromeBacking" "continuous dark Safari chrome backing for loaded pages"
require_pattern "$split_view_file" "chromeBaseColor" "shared loaded-page chrome base color"
require_pattern "$split_view_file" "GlassEffectContainer" "native Liquid Glass container for custom chrome controls"
require_pattern "$split_view_file" "\\.glassEffect\\(" "native Liquid Glass effect for custom chrome controls"
require_pattern "$split_view_file" "\\.buttonStyle\\(\\.glass\\)" "native Liquid Glass button style for toolbar buttons"
require_pattern "$split_view_file" "SafariWindowChromeConfigurator" "full-size transparent titlebar configurator"
require_pattern "$split_view_file" "window\\.styleMask\\.insert\\(\\.fullSizeContentView\\)" "content extends under titlebar"
require_pattern "$split_view_file" "window\\.titlebarAppearsTransparent = true" "transparent titlebar"
require_pattern "$split_view_file" "window\\.isOpaque = false" "transparent window backing"
require_pattern "$split_view_file" "GlassPill" "liquid glass control capsules"
require_pattern "$split_view_file" "ToolbarActionPill" "Safari-style trailing action capsule"
require_pattern "$split_view_file" "SeparateTabBar" "separate Safari-style tab bar"
require_pattern "$split_view_file" "CompactTabStrip" "compact tab strip"
require_pattern "$split_view_file" "AddressField" "Smart Search field"
require_pattern "$split_view_file" "\\.textFieldStyle\\(\\.plain\\)" "custom glass Smart Search text field styling"
require_pattern "$split_view_file" "SafariStartPageView" "Safari-style start page background"
require_pattern "$split_view_file" "TabContextMenu" "tab context menu"
require_pattern "$split_view_file" "Close Other Tabs" "close other tabs UI action"
require_pattern "$split_view_file" "isPageLoading \\? \"xmark\" : \"arrow\\.clockwise\"" "stable reload/stop icon swap"
require_pattern "$split_view_file" "\\.frame\\(width: 16, height: 16\\)" "fixed reload/stop symbol frame"
require_pattern "$split_view_file" "FaviconIcon" "shared favicon rendering view"
require_pattern "$split_view_file" "FaviconLoader\\.shared\\.image" "tab UI favicon loading"

require_pattern "$preferences_file" "enum BrowserTabLayout" "BrowserTabLayout preference model"
require_pattern "$preferences_file" "self\\.tabLayout = \\.separate" "separate tab layout default"
require_pattern "$settings_file" "Picker\\(\"Tab layout\"" "tab layout settings picker"
require_pattern "$input_file" "return \\.page\\(urlString: searchEngine\\.searchURL\\(for: trimmed\\)\\)" "natural language searches web instead of creating AI question turns"

if rg -q "NavigationSplitView|BrowserSidebar|ThreadTimeline|ThreadHeader|ChatInput|PromptTextEditor|WindowResponseAura|GemmaLocalAIAvailabilityBar|Download Gemma|Downloads about 2\\.6 GB" "$split_view_file"; then
    echo "BrowserSplitView must not expose the old sidebar/AI shell." >&2
    exit 1
fi

if rg -q "BrowserToolbar|ToolbarItemGroup|ToolbarItem\\(placement:|SafariChromeBackground|ChromeIconButton|CompactBrowserChrome|SeparateBrowserChrome" "$split_view_file"; then
    echo "BrowserSplitView must use the custom full-size glass chrome overlay instead of toolbar/fake-toolbar surfaces." >&2
    exit 1
fi

if rg -q "\\.fill\\(\\.regularMaterial\\)|\\.overlay\\(tint\\)" "$split_view_file"; then
    echo "BrowserSplitView must use native Liquid Glass APIs for chrome controls instead of manual material/tint overlays." >&2
    exit 1
fi

if rg -q "toolbarBackgroundVisibility\\(\\.hidden, for: \\.windowToolbar\\)" "$detail_view_file"; then
    echo "BrowserDetailView must not hide the native window toolbar material." >&2
    exit 1
fi

if rg -q "appendQuestionTurnToSelectedThread|isGeneratingResponse|gemmaLocalAIAvailability|prepareGemmaLocalAI|codexACPRespondersByThreadID|claudeACPRespondersByThreadID" "$model_file"; then
    echo "BrowserModel must not route default address submissions through sidebar AI." >&2
    exit 1
fi

if rg -q "Picker\\(\"Assistant\"|Gemma LiteRT Local|Codex via ACP|Claude via ACP|download about 2\\.6 GB" "$settings_file"; then
    echo "General settings must not expose AI provider or local model download prompts by default." >&2
    exit 1
fi

if rg -q "Tungsten\\.BrowserThreads\\.v1" "$tab_store_file"; then
    echo "BrowserTabStore must use fresh tab persistence keys and leave legacy thread stores untouched." >&2
    exit 1
fi

if ! awk '
    /func activate\(tab: BrowserTab, isIncognito: Bool, configure: \(BrowserPageSession\) -> Void\)/ { in_activate = 1 }
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
    echo "LivePageSessionHost.activate must close the active CEF page before creating a hibernated-tab replacement session." >&2
    exit 1
fi

echo "ThreadBrowserLifecycleTests passed"
