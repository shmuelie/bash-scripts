#!/usr/bin/env bash
# nvm-common.sh — load nvm.sh (the bash nvm) into the current process.
#
# The PowerShell module targets nvm-windows (an executable); this port targets
# nvm.sh (https://github.com/nvm-sh/nvm), which is a shell function that must be
# sourced. Read/install/alias operations work from a subprocess; `use` only
# affects the invoking process (a child cannot change the parent shell's PATH).

if [[ -n "${_SHM_NVM_COMMON_SOURCED:-}" ]]; then
    return 0
fi
_SHM_NVM_COMMON_SOURCED=1

nvm_dir() {
    printf '%s\n' "${NVM_DIR:-$HOME/.nvm}"
}

# load_nvm — source nvm.sh, or die with an install hint.
load_nvm() {
    local sh; sh="$(nvm_dir)/nvm.sh"
    if [[ ! -s "$sh" ]]; then
        die "nvm not found at $sh. Install nvm.sh: https://github.com/nvm-sh/nvm"
    fi
    # shellcheck disable=SC1090
    . "$sh" >/dev/null 2>&1
}

# nvm_installed — return 0 if nvm.sh is present.
nvm_installed() {
    [[ -s "$(nvm_dir)/nvm.sh" ]]
}
