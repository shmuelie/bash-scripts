#!/usr/bin/env bash
# A local installer fixture. It never contacts Microsoft or installs a real SDK.
set -euo pipefail
printf 'installer:%s\n' "$*" >> "$CALL_LOG"
[[ "${SDK_INSTALL_FAIL:-0}" == 0 ]] || exit "$SDK_INSTALL_FAIL"
directory=''; version=''; preview=0; preserve=0; no_path=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir) directory="$2"; shift 2 ;;
        --version) version="$2"; shift 2 ;;
        --architecture|--channel|--quality|--zip-path) shift 2 ;;
        --no-path) no_path=1; shift ;;
        --dry-run) preview=1; shift ;;
        --skip-non-versioned-files) preserve=1; shift ;;
        *) echo "Unexpected installer argument: $1" >&2; exit 98 ;;
    esac
done
[[ "$no_path" == 1 ]] || exit 97
if [[ "$preview" == 1 ]]; then
    printf 'dotnet-install: Repeatable invocation: ./dotnet-install.sh --version "%s"\n' "${SDK_RESOLVED_VERSION:-8.0.412}"
    [[ "${SDK_DUPLICATE_RESOLUTION:-0}" == 0 ]] || echo 'Repeatable invocation: ./dotnet-install.sh --version "9.0.100"'
    exit 0
fi
[[ "${SDK_EMPTY_INSTALL:-0}" == 0 ]] || exit 0
mkdir -p "$directory/sdk/$version"
: > "$directory/sdk/$version/dotnet.dll"
if [[ "$preserve" == 0 || ! -f "$directory/dotnet" ]]; then
    # ELF/Mach-O architecture is real; execution uses the local 'exec' script.
    cp "$(command -v bash)" "$directory/dotnet"
fi
