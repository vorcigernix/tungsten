#!/usr/bin/env bash
set -euo pipefail

app_protocol_file="Tungsten/Tungsten/CEF/TungstenCrAppProtocol.m"
cef_header="Vendor/CEF/current/include/cef_application_mac.h"

if ! rg -q -- "@protocol CrAppControlProtocol" "$cef_header" ||
   ! rg -q -- "- \\(void\\)setHandlingSendEvent:\\(BOOL\\)handlingSendEvent;" "$cef_header"; then
    echo "CEF macOS header must still require CrAppControlProtocol.setHandlingSendEvent: before this regression test is meaningful." >&2
    exit 1
fi

if ! rg -q -- "- \\(void\\)setHandlingSendEvent:\\(BOOL\\)handlingSendEvent;" "$app_protocol_file"; then
    echo "TungstenCrAppProtocol must implement CEF's setHandlingSendEvent: selector; native context-menu dispatch sends it to NSApp." >&2
    exit 1
fi

if ! awk '
    /static BOOL g_tungstenHandlingSendEvent/ { found_state = 1 }
    /- \(BOOL\)isHandlingSendEvent/ { in_getter = 1 }
    in_getter && /return g_tungstenHandlingSendEvent;/ { getter_reads_state = 1 }
    in_getter && /^}/ { in_getter = 0 }
    /- \(void\)setHandlingSendEvent:\(BOOL\)handlingSendEvent/ { in_setter = 1 }
    in_setter && /g_tungstenHandlingSendEvent = handlingSendEvent;/ { setter_writes_state = 1 }
    in_setter && /^}/ { in_setter = 0 }
    END { exit found_state && getter_reads_state && setter_writes_state ? 0 : 1 }
' "$app_protocol_file"; then
    echo "TungstenCrAppProtocol must store CEF's send-event state so CrAppControlProtocol behaves like Chromium expects." >&2
    exit 1
fi

echo "CEFCrAppProtocolTests passed"
