#!/usr/bin/env bash
set -euo pipefail

preferences_file="Tungsten/Tungsten/AppPreferences.swift"
settings_file="Tungsten/Tungsten/Settings/GeneralSettingsView.swift"
bridge_file="Tungsten/Tungsten/CEF/TungstenCEFBridge.mm"
cef_app_header="Tungsten/Tungsten/CEF/TungstenCEFApp.h"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing $label" >&2
        exit 1
    fi
}

require_pattern "$preferences_file" "enum LocalAIProvider" "LocalAIProvider model"
require_pattern "$preferences_file" "case google" "Google Local AI option"
require_pattern "$preferences_file" "case apple" "Apple Local AI option"
require_pattern "$preferences_file" "case disabled" "Disabled Local AI option"
require_pattern "$preferences_file" "TungstenLocalAIProviderDefaultsKey" "Local AI persistence key (shared via bridging header)"
require_pattern "$settings_file" "Picker\\(\"Local AI\"" "Local AI settings picker"

require_pattern "$cef_app_header" "FOUNDATION_EXPORT NSString \\*const TungstenLocalAIProviderDefaultsKey" "Local AI defaults key declaration"
require_pattern "$bridge_file" "TungstenLocalAIProviderDefaultsKey = @\"Tungsten.LocalAIProvider.v1\"" "Local AI defaults key definition"

require_pattern "$bridge_file" "AIPromptAPI" "Gemini Nano prompt feature"
require_pattern "$bridge_file" "AIPromptAPIMultimodalInput" "Gemini Nano multimodal feature"
require_pattern "$bridge_file" "OptimizationGuideOnDeviceModel" "Optimization Guide local model feature"
require_pattern "$bridge_file" "OnDeviceModelPerformanceParams" "Optimization Guide on-device model flag parameters"
require_pattern "$bridge_file" "TungstenLocalAIProviderDefaultsKey" "CEF Local AI preference lookup"

if ! awk '
    /windowInfo\.runtime_style = CEF_RUNTIME_STYLE_ALLOY/ { found_alloy = 1 }
    /windowInfo\.runtime_style = CEF_RUNTIME_STYLE_CHROME/ { found_chrome = 1 }
    END { exit !(found_alloy && !found_chrome) }
' "$bridge_file"; then
    echo "CEF browser windows with parent NSViews must stay Alloy style; Chromium local AI is controlled by Tungsten settings instead of chrome://flags." >&2
    exit 1
fi

echo "LocalAISettingsTests passed"
