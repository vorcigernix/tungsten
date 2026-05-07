#!/usr/bin/env bash
set -euo pipefail

bridge_file="Tungsten/Tungsten/CEF/TungstenCEFBridge.mm"

if awk '
    /^- \(void\)dealloc/ { in_dealloc = 1 }
    in_dealloc && /^}/ { in_dealloc = 0 }
    in_dealloc && /CloseBrowser/ { found = 1 }
    END { exit found ? 0 : 1 }
' "$bridge_file"; then
    echo "TungstenCEFBridge dealloc must not call CloseBrowser; CEF closes asynchronously during view teardown." >&2
    exit 1
fi

echo "CEFTeardownTests passed"
