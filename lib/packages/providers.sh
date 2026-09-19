#!/usr/bin/env bash
# Canonical wrappers own native invocation; adapters own selection and observation.

packages_require_tool() {
    if ! have_cmd "$1"; then
        printf 'Optional command %s is unavailable; nothing was installed.\n' "$1"
        return 1
    fi
}

packages_npm_available() { packages_require_tool npm; }
packages_pip_available() { packages_require_tool pip; }
packages_uv_available() { packages_require_tool uv; }
packages_vscode_available() { packages_require_tool code; }
packages_dotnet_available() {
    packages_require_tool dotnet || return 1
    local sdks
    sdks="$(dotnet --list-sdks)" || return 2
    if [[ -z "$sdks" ]]; then
        printf 'No .NET SDK is installed; nothing was installed.\n'
        return 1
    fi
}

packages_normalize() {
    local kind="$1" raw="$2"
    package_validate_inventory <<< "$raw" || return 1
    jq -e 'all(.[]; (.latest // .latest_version // null) | . == null or type == "string")' \
        <<< "$raw" >/dev/null || { log_error 'Invalid proposed package version.'; return 1; }
    jq -c --arg kind "$kind" 'map({target:($kind + ":" + .name), name, kind:$kind, version,
        proposedVersion:(.latest // .latest_version // null)})' <<< "$raw"
}

packages_npm_discover() {
    local raw name
    raw="$("$_SHM_ROOT/bin/npm-package" list --global --outdated --json)" || return $?
    while IFS= read -r name; do package_validate_npm "$name" || return 1; done < <(jq -r '.[].name' <<< "$raw")
    packages_normalize global "$raw"
}

packages_pip_list() {
    local options="$1" outdated="$2"
    local -a args=(list --json)
    [[ "$(jq -r '.user // false' <<< "$options")" != true ]] || args+=(--user)
    if [[ "$outdated" == 1 ]]; then
        args+=(--state outdated)
        [[ "$(jq -r 'if has("topLevel") then .topLevel else true end' <<< "$options")" != true ]] || args+=(--top-level)
    fi
    "$_SHM_ROOT/bin/pip-package" "${args[@]}"
}

packages_pip_discover() {
    local raw name
    raw="$(packages_pip_list "$1" 1)" || return $?
    while IFS= read -r name; do package_validate_python "$name" || return 1; done < <(jq -r '.[].name' <<< "$raw")
    packages_normalize package "$raw"
}

packages_dotnet_discover() {
    local raw
    raw="$("$_SHM_ROOT/bin/dotnet-tool" list "$(jq -r '.name // "*"' <<< "$1")" --json)" || return $?
    raw="$(jq -c 'map({name:.packageId,version})' <<< "$raw")" || return 1
    local name
    while IFS= read -r name; do package_validate_dotnet "$name" || return 1; done < <(jq -r '.[].name' <<< "$raw")
    packages_normalize global-tool "$raw"
}

packages_uv_discover() {
    local options="$1" scope raw packages='[]' tools='[]' name
    scope="$(jq -r '.scope // "All"' <<< "$options")"
    if [[ "$scope" != Tools ]]; then
        local -a args=(list --outdated --json)
        [[ "$(jq -r 'if has("topLevel") then .topLevel else true end' <<< "$options")" != true ]] || args+=(--top-level)
        raw="$("$_SHM_ROOT/bin/uv-package" "${args[@]}")" || return $?
        packages="$(packages_normalize package "$raw")" || return 1
    fi
    if [[ "$scope" != Packages ]]; then
        raw="$("$_SHM_ROOT/bin/uv-tool" list --json)" || return $?
        tools="$(packages_normalize tool "$raw")" || return 1
    fi
    raw="$(jq -cn --argjson p "$packages" --argjson t "$tools" '$p + $t')"
    while IFS= read -r name; do package_validate_python "$name" || return 1; done < <(jq -r '.[].name' <<< "$raw")
    printf '%s\n' "$raw"
}

packages_observed_version() {
    local name="$1" inventory="$2"
    package_validate_inventory <<< "$inventory" || return 1
    jq -ce --arg n "$name" '
        def normalized: ascii_downcase | gsub("[-_.]+";"-");
        map(select((.name|normalized) == ($n|normalized))) |
        if length == 1 then {resultingVersion:.[0].version}
        else error("Could not uniquely observe installed version for " + $n) end' <<< "$inventory"
}

packages_npm_update() {
    local name raw
    name="$(jq -r .name <<< "$1")"
    "$_SHM_ROOT/bin/npm-package" update "$name" --global >&2 || return $?
    raw="$("$_SHM_ROOT/bin/npm-package" list --global --json)" || return $?
    # npm identifiers are case-sensitive; do not use Python name normalization.
    jq -ce --arg n "$name" 'map(select(.name == $n)) |
        if length == 1 and (.[0].version | type == "string" and length > 0)
        then {resultingVersion:.[0].version} else error("Unknown installed npm version") end' <<< "$raw"
}

packages_pip_update() {
    local name raw
    name="$(jq -r .name <<< "$1")"
    "$_SHM_ROOT/bin/pip-package" update "$name" >&2 || return $?
    raw="$(packages_pip_list "$2" 0)" || return $?
    packages_observed_version "$name" "$raw"
}

packages_dotnet_update() {
    local name raw
    name="$(jq -r .name <<< "$1")"
    "$_SHM_ROOT/bin/dotnet-tool" update "$name" >&2 || return $?
    raw="$("$_SHM_ROOT/bin/dotnet-tool" list --json)" || return $?
    jq -ce --arg n "$name" 'map(select((.packageId|ascii_downcase) == ($n|ascii_downcase))) |
        if length == 1 and (.[0].version | type == "string" and length > 0)
        then {resultingVersion:.[0].version} else error("Unknown installed tool version") end' <<< "$raw"
}

packages_uv_update() {
    local name kind raw
    name="$(jq -r .name <<< "$1")"; kind="$(jq -r .kind <<< "$1")"
    if [[ "$kind" == tool ]]; then
        "$_SHM_ROOT/bin/uv-tool" update "$name" >&2 || return $?
        raw="$("$_SHM_ROOT/bin/uv-tool" list --json)" || return $?
    else
        "$_SHM_ROOT/bin/uv-package" update "$name" >&2 || return $?
        raw="$("$_SHM_ROOT/bin/uv-package" list --json)" || return $?
    fi
    packages_observed_version "$name" "$raw"
}

packages_vscode_inventory() {
    local profile="$1"
    local -a args=(list --json)
    [[ -z "$profile" ]] || args+=(--profile "$profile")
    "$_SHM_ROOT/bin/vscode-ext" "${args[@]}"
}

packages_vscode_discover() {
    local profile inventory rows='[]' target
    while IFS= read -r profile; do
        inventory="$(packages_vscode_inventory "$profile")" || return $?
        target="extensions (default profile)"
        [[ -z "$profile" ]] || target="extensions (profile: $profile)"
        rows="$(jq -c --arg p "$profile" --arg t "$target" --argjson i "$inventory" \
            '. + [{target:$t, profile:$p, inventory:$i, version:null, proposedVersion:null}]' <<< "$rows")" || return 1
    done < <(jq -r '[""] + ((.profiles // []) | unique) | .[]' <<< "$1")
    printf '%s\n' "$rows"
}

packages_vscode_update() {
    local profile inventory
    profile="$(jq -r .profile <<< "$1")"
    local -a args=(update)
    [[ -z "$profile" ]] || args+=(--profile "$profile")
    "$_SHM_ROOT/bin/vscode-ext" "${args[@]}" >&2 || return $?
    inventory="$(packages_vscode_inventory "$profile")" || return $?
    jq -cn --argjson i "$inventory" '{bulk:true,status:"Updated",resultingVersion:null,
        resultingInventory:$i,reason:"Native bulk update completed for this profile; individual extension outcomes are not reported."}'
}

packages_register npm packages_npm_available packages_npm_discover packages_npm_update
packages_register pip packages_pip_available packages_pip_discover packages_pip_update
packages_register dotnet packages_dotnet_available packages_dotnet_discover packages_dotnet_update
packages_register uv packages_uv_available packages_uv_discover packages_uv_update
packages_register vscode packages_vscode_available packages_vscode_discover packages_vscode_update
