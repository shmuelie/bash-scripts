#!/usr/bin/env bash
# test.sh — run lint, the public-content scan, and the bats test suite.
set -euo pipefail
repo_root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$repo_root"

echo "== Syntax check =="
while IFS= read -r f; do
    bash -n "$f"
done < <(find bin -type f; find lib -type f -name '*.sh')
echo "syntax: clean"

echo "== Lint =="
./build/lint.sh

echo "== Public-content scan =="
./build/scan.sh

echo "== Tests =="
if command -v bats >/dev/null 2>&1; then
    bats test
else
    echo "bats not found; skipping test suite. Install bats-core to run tests." >&2
fi
