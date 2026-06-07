#!/usr/bin/env bash
set -euo pipefail

site_file="site/index.html"
site_readme="site/README.md"
github_url="https://github.com/vorcigernix/tungsten"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

require_pattern "$site_file" "$github_url" "GitHub project download destination"
require_pattern "$site_readme" "$github_url" "GitHub project download documentation"

require_pattern "$site_file" "Block third-party cookies" "third-party cookie privacy feature copy"
require_pattern "$site_file" "Prevent WebRTC IP leaks" "WebRTC privacy feature copy"
require_pattern "$site_file" "Reduce fingerprinting surface" "fingerprinting privacy feature copy"
require_pattern "$site_file" "uBlock-style content blocking" "content blocking feature copy"
require_pattern "$site_file" "Advanced privacy" "advanced privacy feature copy"
require_pattern "$site_file" "Duck AI" "Duck AI default page copy"

if rg -q "\\.\\./dist/Tungsten-[0-9]" "$site_file" "$site_readme"; then
    echo "Microsite download links must point to the GitHub project, not local DMG artifacts." >&2
    exit 1
fi

echo "MicrositeContentTests passed"
