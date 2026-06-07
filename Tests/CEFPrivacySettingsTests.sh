#!/usr/bin/env bash
set -euo pipefail

preferences_file="Tungsten/Sources/Tungsten/Application/AppPreferences.swift"
settings_file="Tungsten/Sources/Tungsten/Settings/GeneralSettingsView.swift"
cef_header="Tungsten/Sources/Tungsten/CEF/TungstenCEFApp.h"
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

require_pattern "$preferences_file" "thirdPartyCookieBlockingEnabled.*Bool" "third-party cookie blocking preference"
require_pattern "$preferences_file" "thirdPartyCookieBlockingEnabled = true" "third-party cookie blocking on-by-default initialization"
require_pattern "$preferences_file" "webRTCIPLeakProtectionEnabled.*Bool" "WebRTC IP leak protection preference"
require_pattern "$preferences_file" "webRTCIPLeakProtectionEnabled = true" "WebRTC IP leak protection on-by-default initialization"
require_pattern "$preferences_file" "fingerprintSurfaceReductionEnabled.*Bool" "fingerprint surface reduction preference"
require_pattern "$preferences_file" "fingerprintSurfaceReductionEnabled = true" "fingerprint surface reduction on-by-default initialization"
require_pattern "$preferences_file" "webGLDisabled.*Bool" "WebGL advanced privacy preference"
require_pattern "$preferences_file" "remoteFontsDisabled.*Bool" "remote fonts advanced privacy preference"
require_pattern "$preferences_file" "javaScriptClipboardAccessDisabled.*Bool" "JavaScript clipboard advanced privacy preference"
require_pattern "$preferences_file" "localStorageDisabled.*Bool" "local storage advanced privacy preference"

require_pattern "$settings_file" "Block third-party cookies" "third-party cookie settings toggle"
require_pattern "$settings_file" "Prevent WebRTC IP leaks" "WebRTC leak settings toggle"
require_pattern "$settings_file" "Reduce fingerprinting surface" "fingerprint surface reduction settings toggle"
require_pattern "$settings_file" "Advanced privacy" "advanced privacy disclosure"
require_pattern "$settings_file" "Disable WebGL" "WebGL settings toggle"
require_pattern "$settings_file" "Disable remote fonts" "remote fonts settings toggle"
require_pattern "$settings_file" "Block JavaScript clipboard access" "JavaScript clipboard settings toggle"
require_pattern "$settings_file" "Disable local storage" "local storage settings toggle"

require_pattern "$cef_header" "TungstenThirdPartyCookieBlockingEnabledDefaultsKey" "third-party cookie defaults key declaration"
require_pattern "$cef_header" "TungstenWebRTCIPLeakProtectionEnabledDefaultsKey" "WebRTC defaults key declaration"
require_pattern "$cef_header" "TungstenFingerprintSurfaceReductionEnabledDefaultsKey" "fingerprint surface reduction defaults key declaration"
require_pattern "$cef_header" "TungstenWebGLDisabledDefaultsKey" "WebGL defaults key declaration"
require_pattern "$cef_header" "TungstenRemoteFontsDisabledDefaultsKey" "remote fonts defaults key declaration"
require_pattern "$cef_header" "TungstenJavaScriptClipboardAccessDisabledDefaultsKey" "JavaScript clipboard defaults key declaration"
require_pattern "$cef_header" "TungstenLocalStorageDisabledDefaultsKey" "local storage defaults key declaration"

require_pattern "$cef_bridge_file" "profile\\.block_third_party_cookies" "CEF third-party cookie preference"
require_pattern "$cef_bridge_file" "configurePrivacyRequestContextPreferences" "CEF privacy request-context configuration"
require_pattern "$cef_bridge_file" "webrtc\\.ip_handling_policy" "CEF WebRTC IP handling preference"
require_pattern "$cef_bridge_file" "disable_non_proxied_udp" "CEF WebRTC non-proxied UDP guard"
require_pattern "$cef_bridge_file" "webrtc\\.multiple_routes_enabled" "CEF WebRTC multiple route guard"
require_pattern "$cef_bridge_file" "SetContentSetting\\(\"\", \"\", CEF_CONTENT_SETTING_TYPE_LOCAL_FONTS, CEF_CONTENT_SETTING_VALUE_BLOCK\\)" "CEF local fonts content setting"
require_pattern "$cef_bridge_file" "CEF_CONTENT_SETTING_TYPE_SENSORS" "CEF sensors content setting"
require_pattern "$cef_bridge_file" "CEF_CONTENT_SETTING_TYPE_IDLE_DETECTION" "CEF idle detection content setting"
require_pattern "$cef_bridge_file" "CEF_CONTENT_SETTING_TYPE_NOTIFICATIONS" "CEF notifications content setting"
require_pattern "$cef_bridge_file" "CEF_CONTENT_SETTING_TYPE_WINDOW_MANAGEMENT" "CEF window management content setting"
require_pattern "$cef_bridge_file" "privacy_sandbox\\.m1\\.topics_enabled" "CEF Topics API preference"
require_pattern "$cef_bridge_file" "privacy_sandbox\\.m1\\.fledge_enabled" "CEF FLEDGE API preference"
require_pattern "$cef_bridge_file" "privacy_sandbox\\.m1\\.ad_measurement_enabled" "CEF ad measurement preference"
require_pattern "$cef_bridge_file" "privacy_sandbox\\.first_party_sets_enabled" "CEF related website sets preference"
require_pattern "$cef_bridge_file" "enable_a_ping" "CEF hyperlink auditing preference"
require_pattern "$cef_bridge_file" "GetPermissionHandler" "CEF permission handler"
require_pattern "$cef_bridge_file" "CEF_PERMISSION_TYPE_LOCAL_FONTS" "CEF local fonts permission denial"
require_pattern "$cef_bridge_file" "CEF_PERMISSION_RESULT_DENY" "CEF fingerprint permission denial result"
require_pattern "$cef_bridge_file" "browserSettings\\.webgl = STATE_DISABLED" "CEF WebGL browser setting"
require_pattern "$cef_bridge_file" "browserSettings\\.remote_fonts = STATE_DISABLED" "CEF remote fonts browser setting"
require_pattern "$cef_bridge_file" "browserSettings\\.javascript_access_clipboard = STATE_DISABLED" "CEF JavaScript clipboard browser setting"
require_pattern "$cef_bridge_file" "browserSettings\\.javascript_dom_paste = STATE_DISABLED" "CEF JavaScript DOM paste browser setting"
require_pattern "$cef_bridge_file" "browserSettings\\.local_storage = STATE_DISABLED" "CEF local storage browser setting"

echo "CEFPrivacySettingsTests passed"
