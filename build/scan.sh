#!/usr/bin/env bash
# scan.sh — public-content policy scan, ported from Test-Modules.ps1.
#
# These scripts are for public distribution and must not reference internal-only
# tooling, private endpoints, organization-specific systems, or credentials.
# This scan fails on forbidden markers and on broken local Markdown links.
set -euo pipefail
repo_root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$repo_root"

fail=0
err() { printf 'scan: %s\n' "$*" >&2; fail=1; }

# --- Forbidden markers ------------------------------------------------------
# Case-insensitive substrings that indicate non-public content leaked in.
# Extend this list as needed; keep it conservative to avoid false positives.
forbidden=(
    'INTERNAL-ONLY'
    'DO-NOT-SHIP'
    'CONFIDENTIAL'
    'BEGIN RSA PRIVATE KEY'
    'BEGIN OPENSSH PRIVATE KEY'
    'xoxb-'          # Slack bot token prefix
    'ghp_'           # GitHub personal access token prefix
    'AKIA'           # AWS access key id prefix
)

mapfile -t scan_files < <(
    find bin lib completions build test -type f 2>/dev/null | grep -v '^build/scan.sh$'
    find . -maxdepth 1 -type f -name '*.md' 2>/dev/null
    find docs -type f -name '*.md' 2>/dev/null
)

for marker in "${forbidden[@]}"; do
    if matches="$(grep -rInF -- "$marker" "${scan_files[@]}" 2>/dev/null)"; then
        err "forbidden marker '$marker' found:"
        printf '%s\n' "$matches" >&2
    fi
done

# --- Broken local Markdown links -------------------------------------------
check_md_links() {
    local md="$1" dir target local_path
    dir="$(dirname -- "$md")"
    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        case "$target" in
            http:*|https:*|mailto:*|\#*) continue ;;
        esac
        local_path="${target%%#*}"
        [[ -z "$local_path" ]] && continue
        if [[ ! -e "$dir/$local_path" ]]; then
            err "broken local link in $md: $target"
        fi
    done < <(grep -oE '\[[^]]*\]\(([^)]+)\)' "$md" 2>/dev/null | sed -E 's/.*\(([^)]+)\)/\1/')
}

while IFS= read -r md; do
    check_md_links "$md"
done < <(find . -maxdepth 1 -name '*.md'; find docs -name '*.md' 2>/dev/null)

# --- CHANGELOG [Unreleased] section ----------------------------------------
if [[ -f CHANGELOG.md ]] && ! grep -qE '^##[[:space:]]*\[Unreleased\]' CHANGELOG.md; then
    err "CHANGELOG.md is missing an [Unreleased] section."
fi

if [[ "$fail" == "0" ]]; then
    echo "scan: clean"
else
    echo "scan: FAILED" >&2
fi
exit "$fail"
