#!/usr/bin/env bash
set -euo pipefail

workflow_file=".github/workflows/pages.yml"

require_pattern() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if ! rg -q "$pattern" "$file"; then
        echo "Missing ${description} in ${file}" >&2
        exit 1
    fi
}

if [[ ! -f "$workflow_file" ]]; then
    echo "Missing GitHub Pages workflow at ${workflow_file}" >&2
    exit 1
fi

require_pattern "$workflow_file" "branches: \\[main\\]" "main branch Pages trigger"
require_pattern "$workflow_file" "contents: read" "read-only repository permission"
require_pattern "$workflow_file" "pages: write" "GitHub Pages write permission"
require_pattern "$workflow_file" "id-token: write" "OIDC token permission for Pages deploy"
require_pattern "$workflow_file" "environment:" "GitHub Pages deployment environment"
require_pattern "$workflow_file" "name: github-pages" "github-pages environment name"
require_pattern "$workflow_file" "actions/checkout@v6" "current checkout action"
require_pattern "$workflow_file" "actions/configure-pages@v5" "GitHub Pages configuration action"
require_pattern "$workflow_file" "actions/upload-pages-artifact@v4" "GitHub Pages artifact upload action"
require_pattern "$workflow_file" "path: site" "site folder artifact path"
require_pattern "$workflow_file" "actions/deploy-pages@v4" "GitHub Pages deployment action"

if rg -q "path: \\." "$workflow_file"; then
    echo "GitHub Pages workflow must publish site/, not the repository root." >&2
    exit 1
fi

echo "GitHubPagesWorkflowTests passed"
