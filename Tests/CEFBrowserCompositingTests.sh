#!/usr/bin/env bash
set -euo pipefail

bridge_file="Tungsten/Sources/Tungsten/CEF/TungstenCEFBridge.mm"

if ! grep -q "NonVibrantBrowserAppearanceForWindow" "$bridge_file"; then
    echo "CEF browser compositing must choose a non-vibrant Aqua/DarkAqua appearance for web content." >&2
    exit 1
fi

if ! grep -q "NSAppearanceNameAqua" "$bridge_file" || ! grep -q "NSAppearanceNameDarkAqua" "$bridge_file"; then
    echo "CEF browser compositing must preserve light/dark mode without inheriting vibrant appearances." >&2
    exit 1
fi

if ! grep -q "ApplyCEFSubviewCompositing" "$bridge_file"; then
    echo "CEF browser compositing must recursively mark the Chromium NSView subtree as opaque/non-vibrant." >&2
    exit 1
fi

if ! awk '/windowFocusOrBackingDidChange:/,/^}/' "$bridge_file" | grep -q "layoutBrowserView"; then
    echo "CEF browser compositing must be reapplied when the host window changes focus/backing state." >&2
    exit 1
fi

echo "CEFBrowserCompositingTests passed"
