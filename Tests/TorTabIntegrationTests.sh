#!/usr/bin/env bash
set -euo pipefail

tab_file="Tungsten/Sources/Tungsten/Browser/Tabs/BrowserTab.swift"
model_file="Tungsten/Sources/Tungsten/Browser/BrowserModel.swift"
preferences_file="Tungsten/Sources/Tungsten/Application/AppPreferences.swift"
settings_file="Tungsten/Sources/Tungsten/Settings/GeneralSettingsView.swift"
tor_service_file="Tungsten/Sources/Tungsten/Browser/Tor/TorNetworkService.swift"
copy_runtime_script="scripts/copy-cef-runtime.sh"
setup_arti_script="scripts/setup-arti.sh"
build_release_script="scripts/build-release.sh"
package_release_script="scripts/package-release.sh"
shortcut_action_file="Tungsten/Sources/Tungsten/Shortcuts/Core/ShortcutAction.swift"
shortcut_dispatcher_file="Tungsten/Sources/Tungsten/Shortcuts/ShortcutDispatcher.swift"
cef_controller_header="Tungsten/Sources/Tungsten/CEF/TungstenBrowserController.h"
cef_bridge_file="Tungsten/Sources/Tungsten/CEF/TungstenCEFBridge.mm"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_pattern "$tab_file" "enum BrowserTabPrivacyMode" "tab privacy mode model"
require_pattern "$tab_file" "case tor" "Tor tab privacy mode"
require_pattern "$tab_file" "privacyMode.*BrowserTabPrivacyMode" "privacy mode on tab state"

require_pattern "$preferences_file" "torConfiguration" "Tor proxy configuration preference"
require_pattern "$preferences_file" "torArtiExecutablePath" "Arti executable preference"
require_pattern "$preferences_file" "torSocksPort" "Tor SOCKS port preference"
require_pattern "$settings_file" "Start Arti for Tor tabs" "Tor settings launch toggle"
require_pattern "$settings_file" "Arti executable" "Arti executable settings field"
require_pattern "$settings_file" "SOCKS port" "Tor SOCKS port settings field"

require_pattern "$tor_service_file" "final class TorNetworkService" "Tor network service"
require_pattern "$tor_service_file" "\"arti\"" "Arti default executable"
require_pattern "$tor_service_file" "\"proxy\"" "Arti proxy command"
require_pattern "$tor_service_file" "\"-o\"" "Arti config override argument"
require_pattern "$tor_service_file" "proxy\\.socks_listen" "Arti SOCKS listen override"
require_pattern "$tor_service_file" "waitUntilProxyIsListening" "Tor proxy readiness check"
require_pattern "$tor_service_file" "waitUntilTorProxyCanConnect" "Tor bootstrap readiness check"
require_pattern "$tor_service_file" "check\\.torproject\\.org" "Tor bootstrap SOCKS probe target"
require_pattern "$tor_service_file" "Bundle\\.main\\.resourceURL" "bundled Arti lookup"
require_pattern "$tor_service_file" "Vendor/Arti/bin" "development vendor Arti lookup"

require_pattern "$setup_arti_script" "cargo install" "Arti setup Cargo install"
require_pattern "$setup_arti_script" "Vendor/Arti" "Arti setup vendor destination"
require_pattern "$copy_runtime_script" "Vendor/Arti/bin/arti" "Arti runtime copy source"
require_pattern "$copy_runtime_script" "ARTI_RESOURCE_BIN" "Arti runtime copy destination variable"
require_pattern "$copy_runtime_script" "Arti/arti" "Arti runtime copy destination"
require_pattern "$build_release_script" "setup-arti\\.sh" "release build Arti setup"
require_pattern "$build_release_script" "Contents/Resources/Arti/arti" "release build bundled Arti verification"
require_pattern "$package_release_script" "Contents/Resources/Arti/arti" "release package bundled Arti verification"
require_pattern "$package_release_script" "build-release\\.sh" "release package rebuilds when Arti is missing"

if rg -q "\"-p\"" "$tor_service_file"; then
    echo "TorNetworkService still uses Arti's obsolete -p argument" >&2
    exit 1
fi

require_pattern "$shortcut_action_file" "case newIncognitoTab" "new incognito tab shortcut action"
require_pattern "$shortcut_action_file" "case newTorTab" "new Tor tab shortcut action"
require_pattern "$shortcut_dispatcher_file" "createIncognitoTab" "shortcut dispatch for incognito tab"
require_pattern "$shortcut_dispatcher_file" "createTorTab" "shortcut dispatch for Tor tab"
require_pattern "$model_file" "func createIncognitoTab" "browser model incognito tab command"
require_pattern "$model_file" "func createTorTab" "browser model Tor tab command"
require_pattern "$model_file" "appPreferences\\.torConfiguration" "Tor configuration passed to page sessions"

require_pattern "$cef_controller_header" "privacyMode.*NSString" "CEF controller privacy initializer"
require_pattern "$cef_controller_header" "torProxyHost" "CEF controller Tor proxy host parameter"
require_pattern "$cef_bridge_file" "socks5://%@:%d" "CEF SOCKS5 proxy server preference"
require_pattern "$cef_bridge_file" "setRequestContextPreference:\"proxy\"" "CEF request context proxy preference"
require_pattern "$cef_bridge_file" "webrtc\\.ip_handling_policy" "WebRTC non-proxied UDP guard"
require_pattern "Tungsten/Sources/Tungsten/Browser/Threads/BrowserPageSession.swift" "torStartupErrorURL" "Tor startup failure page"
require_pattern "Tungsten/Sources/Tungsten/Browser/Threads/BrowserPageSession.swift" "ensureRunning\\(configuration: torConfiguration\\)" "Tor startup result check"

echo "TorTabIntegrationTests passed"
