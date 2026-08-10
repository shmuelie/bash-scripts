#!/usr/bin/env bash
# lint.sh — run shellcheck across all shell scripts in the repository.
set -euo pipefail
repo_root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$repo_root"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not found on PATH. Install it: https://www.shellcheck.net/" >&2
    exit 1
fi

# Collect bin executables, libraries, completions, build scripts, and installer.
mapfile -t targets < <(
    find bin -type f 2>/dev/null
    find lib -type f -name '*.sh' 2>/dev/null
    find completions/bash -type f -name '*.bash' 2>/dev/null
    find build -type f -name '*.sh' 2>/dev/null
    [ -f install.sh ] && printf '%s\n' install.sh
)

echo "Linting ${#targets[@]} scripts with shellcheck..."
# -x follows sourced files; SC1091 (can't follow source) is expected at lint time.
shellcheck -x -e SC1091 "${targets[@]}"
echo "shellcheck: clean"
