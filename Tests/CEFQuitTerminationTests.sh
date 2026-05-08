#!/usr/bin/env bash
set -euo pipefail

app_file="Tungsten/Tungsten/TungstenApp.swift"
bridge_file="Tungsten/Tungsten/CEF/TungstenCEFBridge.mm"
header_file="Tungsten/Tungsten/CEF/TungstenCEFApp.h"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing $label" >&2
        exit 1
    fi
}

require_pattern "$header_file" "isTerminating" "CEF termination state"
require_pattern "$header_file" "beginTermination" "CEF termination marker"
require_pattern "$app_file" "applicationShouldTerminate" "quit termination hook"
require_pattern "$app_file" "beginTermination" "termination hook marks CEF as terminating"
require_pattern "$bridge_file" "_terminating" "CEF app termination storage"

if ! awk '
    /- \(void\)initializeCEF/ { in_initialize = 1 }
    in_initialize && /_terminating/ { found_initialize_guard = 1 }
    in_initialize && /^}/ { in_initialize = 0 }
    END { exit !found_initialize_guard }
' "$bridge_file"; then
    echo "TungstenCEFApp.initializeCEF must not initialize CEF after quit termination has begun." >&2
    exit 1
fi

if ! awk '
    /- \(void\)createBrowserIfNeeded/ { in_create = 1 }
    in_create && /isTerminating/ { found_create_guard = 1 }
    in_create && /^}/ { in_create = 0 }
    END { exit !found_create_guard }
' "$bridge_file"; then
    echo "TungstenBrowserController.createBrowserIfNeeded must not create or initialize CEF while the app is terminating." >&2
    exit 1
fi

echo "CEFQuitTerminationTests passed"
