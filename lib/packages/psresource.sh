#!/usr/bin/env bash
# Only the canonical Utilities module interprets installed resource metadata.

packages_psresource_bridge() {
    local operation="$1" provider_options="$2" target="${3:-null}"
    jq -cn --arg operation "$operation" --argjson options "$provider_options" --argjson target "$target" \
        '{operation:$operation,options:$options,target:$target}' |
        pwsh -NoLogo -NoProfile -NonInteractive -File "$_SHM_ROOT/lib/packages/psresource.ps1"
}

packages_psresource_available() {
    if [[ "$(jq '.roots // [] | length' <<< "$1")" == 0 ]]; then
        printf 'Configure explicit psresource roots; ambient module paths are not scanned.\n'
        return 1
    fi
    packages_require_tool pwsh || return 1
    local probe code=0
    probe="$(packages_psresource_bridge Probe "$1")" || code=$?
    [[ "$code" == 0 ]] || return 2
    if ! jq -e 'type == "object" and (.available | type == "boolean")' <<< "$probe" >/dev/null; then
        log_error 'Invalid canonical PowerShell availability response.'
        return 2
    fi
    if [[ "$(jq -r .available <<< "$probe")" == false ]]; then
        jq -r '.reason' <<< "$probe"
        return 1
    fi
}

packages_psresource_discover() { packages_psresource_bridge Discover "$1"; }
packages_psresource_update() { packages_psresource_bridge Update "$2" "$1"; }

packages_register psresource packages_psresource_available packages_psresource_discover packages_psresource_update
