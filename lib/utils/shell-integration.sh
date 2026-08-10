#!/usr/bin/env bash
# shell-integration.sh — sourceable helpers that only make sense inside your
# interactive shell (they create shell variables or change shell state).
# Ported from the PowerShell-shell-specific helpers in Utilities.ps1.
#
# Source this from your ~/.bashrc:
#     source /path/to/lib/utils/shell-integration.sh

# shm_global_constant NAME VALUE — define a readonly (constant) shell variable.
# Ported from New-GlobalConstant.
shm_global_constant() {
    local name="$1" value="$2"
    [[ -n "$name" ]] || { echo "shm_global_constant: NAME required" >&2; return 2; }
    declare -gr "$name=$value"
}

# shm_path_constant NAME PATH — define a readonly variable only if PATH exists.
# Ported from New-PathVariable.
shm_path_constant() {
    local name="$1" path="$2"
    if [[ -n "$path" && -e "$path" ]]; then
        shm_global_constant "$name" "$path"
    fi
}

# shm_prepend_path DIR — prepend DIR to PATH if it exists and isn't present.
shm_prepend_path() {
    local dir="$1"
    if [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
        export PATH
    fi
}

# shm_session_title — print a descriptive title for the current shell session.
# Ported from Get-SessionTitle (adapted for bash).
shm_session_title() {
    local title
    title="bash ${BASH_VERSION%%(*} ($(uname -m))"
    if [[ "$(id -u)" -eq 0 ]]; then
        title="🛡️ $title"
    fi
    printf '%s\n' "$title"
}

# shm_source_safe PATH — source a file only if it exists. Ported from
# Import-ModuleSafe.
shm_source_safe() {
    local path="$1"
    if [[ -e "$path" ]]; then
        # shellcheck disable=SC1090
        . "$path"
    fi
}
