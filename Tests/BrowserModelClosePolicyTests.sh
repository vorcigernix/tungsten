#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"

if ! awk '
    /func close\(_ tab: BrowserTab\)/ { in_close = 1 }
    in_close && /tabs\.count == 1/ { saw_single_tab_guard = 1 }
    in_close && /tabs\.remove\(at:/ && !saw_single_tab_guard { exit 1 }
    in_close && /^    }$/ { exit 0 }
' "$model_file"; then
    echo "BrowserModel.close must handle the one-tab case before removing the tab, so CEF is not torn down on Cmd-W." >&2
    exit 1
fi

echo "BrowserModelClosePolicyTests passed"
