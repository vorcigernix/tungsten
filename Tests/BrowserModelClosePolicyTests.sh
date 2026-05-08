#!/usr/bin/env bash
set -euo pipefail

model_file="Tungsten/Tungsten/Browser/BrowserModel.swift"

if ! awk '
    /func close\(_ thread: BrowserThread\)/ { in_close = 1; found = 1 }
    in_close && /threads\.remove\(at: index\)/ { saw_remove = 1 }
    in_close && /if threads\.isEmpty/ { saw_empty_guard = 1 }
    in_close && /createThread\(\)/ { saw_replacement = 1 }
    in_close && /if selectedWasClosed/ { saw_selected_reselect = 1 }
    in_close && /^    }$/ {
        exit (saw_remove && saw_empty_guard && saw_replacement && saw_selected_reselect) ? 0 : 1
    }
    END { if (!found) exit 1 }
' "$model_file"; then
    echo "BrowserModel.close must handle selected/only-thread closure by creating a replacement thread instead of leaving the browser without an active page." >&2
    exit 1
fi

echo "BrowserModelClosePolicyTests passed"
