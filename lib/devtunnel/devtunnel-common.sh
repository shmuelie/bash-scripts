#!/usr/bin/env bash
# Source-only entry point; CLI discovery and authentication are always explicit.
if [[ -n "${_SHM_DEVTUNNEL_SOURCED:-}" ]]; then return 0; fi
_SHM_DEVTUNNEL_SOURCED=1

devtunnel_main() {
    require_cmd python3 'Python 3 is required for dev-tunnel process supervision.'
    exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/devtunnel.py" "$@"
}
