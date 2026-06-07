#!/usr/bin/env bash
set -euo pipefail

cef_bridge="Tungsten/Sources/Tungsten/CEF/TungstenCEFBridge.mm"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q -- "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_pattern "$cef_bridge" "__weak typeof\\(self\\) weakSelf = self;" "weak self capture before page-content timeout"
require_pattern "$cef_bridge" "__strong typeof\\(weakSelf\\) self = weakSelf;" "strong self recovery inside page-content timeout"
require_pattern "$cef_bridge" "\\[self clearPageContentCompletions\\]" "page-content completion cleanup during close"
require_pattern "$cef_bridge" "- \\(void\\)clearPageContentCompletions" "page-content completion cleanup helper"

echo "CEFPageContentLifetimeTests passed"
