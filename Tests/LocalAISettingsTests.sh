#!/usr/bin/env bash
set -euo pipefail

preferences_file="Tungsten/Tungsten/AppPreferences.swift"
provider_file="Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift"
settings_file="Tungsten/Tungsten/Settings/GeneralSettingsView.swift"
split_view_file="Tungsten/Tungsten/Browser/BrowserSplitView.swift"
gemma_file="Tungsten/Tungsten/Browser/AI/GemmaLocalAI.swift"
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

require_pattern "$provider_file" "enum LocalAIProvider" "dormant LocalAIProvider model"
require_pattern "$provider_file" "enum SidebarAssistantProvider" "dormant sidebar assistant provider model"
require_pattern "$preferences_file" "TungstenLocalAIProviderDefaultsKey" "Local AI persistence key remains migratable"
require_pattern "$preferences_file" "assistantProvider" "assistant provider preference remains for dormant source compatibility"
require_pattern "$preferences_file" "self\\.assistantProvider = \\.disabled" "assistant provider disabled default"
require_pattern "$settings_file" "Picker\\(\"Tab layout\"" "visible tab layout settings picker"
require_pattern "$settings_file" "Picker\\(\"Search engine\"" "visible search engine settings picker"
require_pattern "$gemma_file" "liblitert-lm\\.dylib" "Gemma LiteRT local runtime source remains available but dormant"

require_pattern "$cef_app_header" "FOUNDATION_EXPORT NSString \\*const TungstenLocalAIProviderDefaultsKey" "Local AI defaults key declaration"
require_pattern "$bridge_file" "TungstenLocalAIProviderDefaultsKey = @\"Tungsten.LocalAIProvider.v1\"" "Local AI defaults key definition"

if rg -q "Picker\\(\"Assistant\"|Gemma LiteRT Local|Codex via ACP|Claude via ACP|Command|Arguments|download about 2\\.6 GB|app-managed model files|LiteRT runtime" "$settings_file"; then
    echo "General settings must not expose AI providers or local model download prompts by default." >&2
    exit 1
fi

if rg -q "GemmaLocalAIAvailabilityBar|Download Gemma|Downloads about 2\\.6 GB|WindowResponseAura|ChatInput" "$split_view_file"; then
    echo "Browser chrome must not surface local AI setup or sidebar assistant UI by default." >&2
    exit 1
fi

if rg -q "AIPromptAPI|AIPromptAPIMultimodalInput|OptimizationGuideOnDeviceModel|OnDeviceModelPerformanceParams|LanguageModel\\.availability|LanguageModel\\.create" "$bridge_file"; then
    echo "CEF bridge must not depend on CEF Prompt API or Gemini Nano feature flags." >&2
    exit 1
fi

if rg -q "llama\\.cpp|llama-cli|GGUF" "$settings_file"; then
    echo "Default settings must not mention the removed llama.cpp/GGUF path." >&2
    exit 1
fi

if ! awk '
    /windowInfo\.runtime_style = CEF_RUNTIME_STYLE_ALLOY/ { found_alloy = 1 }
    /windowInfo\.runtime_style = CEF_RUNTIME_STYLE_CHROME/ { found_chrome = 1 }
    END { exit !(found_alloy && !found_chrome) }
' "$bridge_file"; then
    echo "CEF browser windows with parent NSViews must stay Alloy style." >&2
    exit 1
fi

echo "LocalAISettingsTests passed"
