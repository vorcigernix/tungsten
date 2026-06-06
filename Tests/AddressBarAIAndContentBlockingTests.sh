#!/usr/bin/env bash
set -euo pipefail

preferences_file="Tungsten/Tungsten/AppPreferences.swift"
settings_file="Tungsten/Tungsten/Settings/GeneralSettingsView.swift"
search_file="Tungsten/Tungsten/Browser/SearchEngine.swift"
browser_model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"
classifier_file="Tungsten/Tungsten/Browser/Threads/BrowserInputClassifier.swift"
cef_header="Tungsten/Tungsten/CEF/TungstenCEFApp.h"
bridge_file="Tungsten/Tungsten/CEF/TungstenCEFBridge.mm"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! grep -Eq "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_pattern "$search_file" "enum AddressBarAIProvider" "address bar AI provider model"
require_pattern "$search_file" "duck\\.ai/chat\\?prompt=1&home=1&q=" "DuckDuckGo AI URL builder"
require_pattern "$search_file" "google\\.com/search\\?udm=50&q=" "Google AI Mode URL builder"
require_pattern "$classifier_file" "return \\.question\\(trimmed\\)" "natural-language question classification"
require_pattern "$browser_model_file" "addressBarAIProvider\\.responseURL" "address bar question provider routing"

require_pattern "$preferences_file" "addressBarAIProviderKey" "address bar AI provider persistence key"
require_pattern "$preferences_file" "contentBlockingEnabled.*Bool" "content blocking preference"
require_pattern "$preferences_file" "contentBlockingEnabled = false" "content blocking off-by-default initialization"
require_pattern "$settings_file" "Address-bar answers" "address bar AI provider settings picker"
require_pattern "$settings_file" "uBlock-style content blocking" "content blocking settings toggle"

require_pattern "$cef_header" "FOUNDATION_EXPORT NSString \\*const TungstenContentBlockingEnabledDefaultsKey" "content blocking defaults key declaration"
require_pattern "$bridge_file" "TungstenContentBlockingEnabledDefaultsKey = @\"Tungsten.ContentBlockingEnabled.v1\"" "content blocking defaults key definition"
require_pattern "$bridge_file" "CefResourceRequestHandler" "CEF resource request handler"
require_pattern "$bridge_file" "OnBeforeResourceLoad" "CEF before-resource-load interception"
require_pattern "$bridge_file" "RV_CANCEL" "CEF request cancellation"

echo "AddressBarAIAndContentBlockingTests passed"
