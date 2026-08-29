#!/usr/bin/env bash
# Resource validation and application helpers for dev-setup.

validate_setup_config() {
    jq -e '
        def nonempty: type == "string" and length > 0;
        def allowed($names): ((keys - $names) | length) == 0;
        def valid_resource:
            type == "object" and
            if .type == "symlink" then
                allowed(["force", "path", "target", "type"]) and
                (.path | nonempty) and (.target | nonempty) and
                ((has("force") | not) or (.force | type == "boolean"))
            elif .type == "copilotPlugin" then
                allowed(["name", "source", "type"]) and
                (.source | nonempty) and
                ((has("name") | not) or (.name | nonempty)) and
                ((.source | test("^[A-Za-z][A-Za-z0-9+.-]*://") | not) or
                 (.name | nonempty))
            elif .type == "copilotMarketplace" then
                allowed(["name", "repository", "type"]) and
                (.name | nonempty) and (.repository | nonempty)
            elif .type == "uvTool" then
                allowed(["name", "type"]) and (.name | nonempty)
            else false
            end;
        type == "object" and
        allowed(["resources", "version"]) and
        .version == 1 and
        (.resources | type == "array") and
        all(.resources[]; valid_resource)
    ' "$1" >/dev/null
}

setup_bin() {
    printf '%s/%s\n' "${SHM_SETUP_BIN_DIR:-$_SHM_ROOT/bin}" "$1"
}

plugin_installed_name() {
    local source="$1" explicit="$2" name
    if [[ -n "$explicit" ]]; then
        printf '%s\n' "$explicit"
        return
    fi
    name="${source#market:}"
    name="${name%%@*}"
    name="${name##*/}"
    name="${name%%#*}"
    name="${name%.git}"
    printf '%s\n' "$name"
}

check_symlink_resource() {
    local resource="$1" path target actual
    path="$(jq -r '.path' <<< "$resource")"
    target="$(jq -r '.target' <<< "$resource")"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        SETUP_MESSAGE="missing link: $path"
        return 1
    fi
    if [[ ! -L "$path" ]]; then
        SETUP_MESSAGE="path exists and is not a symbolic link: $path"
        return 1
    fi
    actual="$(readlink "$path")"
    if [[ "$actual" == "$target" ]]; then
        SETUP_MESSAGE="$path -> $target"
        return 0
    fi
    SETUP_MESSAGE="$path points to $actual instead of $target"
    return 1
}

check_plugin_resource() {
    local resource="$1" source explicit name output
    source="$(jq -r '.source' <<< "$resource")"
    explicit="$(jq -r '.name // ""' <<< "$resource")"
    name="$(plugin_installed_name "$source" "$explicit")"
    if ! output="$("$(setup_bin copilot-plugin)" list --json 2>&1)"; then
        SETUP_MESSAGE="$output"
        return 2
    fi
    if jq -e --arg name "$name" 'any(.[]; .name == $name or .fullName == $name)' \
        <<< "$output" >/dev/null; then
        SETUP_MESSAGE="$name is installed"
        return 0
    fi
    SETUP_MESSAGE="$name is not installed"
    return 1
}

check_marketplace_resource() {
    local resource="$1" name repository output
    name="$(jq -r '.name' <<< "$resource")"
    repository="$(jq -r '.repository' <<< "$resource")"
    if ! output="$("$(setup_bin copilot-marketplace)" list --json 2>&1)"; then
        SETUP_MESSAGE="$output"
        return 2
    fi
    if jq -e --arg name "$name" --arg repository "$repository" \
        'any(.[]; .name == $name and .repository == $repository)' \
        <<< "$output" >/dev/null; then
        SETUP_MESSAGE="$name is registered from $repository"
        return 0
    fi
    SETUP_MESSAGE="$name is not registered from $repository"
    return 1
}

check_uv_tool_resource() {
    local resource="$1" name output
    name="$(jq -r '.name' <<< "$resource")"
    if ! output="$("$(setup_bin uv-tool)" list "$name" --json 2>&1)"; then
        SETUP_MESSAGE="$output"
        return 2
    fi
    if jq -e --arg name "$name" 'any(.[]; .name == $name)' <<< "$output" >/dev/null; then
        SETUP_MESSAGE="$name is installed"
        return 0
    fi
    SETUP_MESSAGE="$name is not installed"
    return 1
}

check_setup_resource() {
    local resource="$1" type
    type="$(jq -r '.type' <<< "$resource")"
    case "$type" in
        symlink) check_symlink_resource "$resource" ;;
        copilotPlugin) check_plugin_resource "$resource" ;;
        copilotMarketplace) check_marketplace_resource "$resource" ;;
        uvTool) check_uv_tool_resource "$resource" ;;
    esac
}

setup_resource_name() {
    local resource="$1" type
    type="$(jq -r '.type' <<< "$resource")"
    case "$type" in
        symlink) jq -r '.path' <<< "$resource" ;;
        copilotPlugin)
            plugin_installed_name \
                "$(jq -r '.source' <<< "$resource")" \
                "$(jq -r '.name // ""' <<< "$resource")"
            ;;
        copilotMarketplace|uvTool) jq -r '.name' <<< "$resource" ;;
    esac
}

apply_symlink_resource() {
    local resource="$1" global_force="$2" path target parent force
    path="$(jq -r '.path' <<< "$resource")"
    target="$(jq -r '.target' <<< "$resource")"
    force="$(jq -r '.force // false' <<< "$resource")"
    [[ "$global_force" == "1" ]] && force=true

    if [[ -e "$path" || -L "$path" ]]; then
        if [[ "$force" != "true" ]]; then
            SETUP_MESSAGE="refusing to replace $path without --force or force: true"
            return 1
        fi
        if [[ -d "$path" && ! -L "$path" ]]; then
            SETUP_MESSAGE="refusing to replace directory: $path"
            return 1
        fi
        rm -f -- "$path" || {
            SETUP_MESSAGE="failed to remove existing path: $path"
            return 1
        }
    fi
    parent="$(dirname "$path")"
    mkdir -p "$parent" || {
        SETUP_MESSAGE="failed to create parent directory: $parent"
        return 1
    }
    if ! ln -s "$target" "$path"; then
        SETUP_MESSAGE="failed to create $path -> $target"
        return 1
    fi
    SETUP_MESSAGE="created $path -> $target"
}

apply_setup_resource() {
    local resource="$1" global_force="$2" type source repository name output
    type="$(jq -r '.type' <<< "$resource")"
    case "$type" in
        symlink)
            apply_symlink_resource "$resource" "$global_force"
            ;;
        copilotPlugin)
            source="$(jq -r '.source' <<< "$resource")"
            if ! output="$("$(setup_bin copilot-plugin)" install "$source" 2>&1)"; then
                SETUP_MESSAGE="$output"
                return 1
            fi
            SETUP_MESSAGE="installed $(setup_resource_name "$resource")"
            ;;
        copilotMarketplace)
            repository="$(jq -r '.repository' <<< "$resource")"
            name="$(jq -r '.name' <<< "$resource")"
            if ! output="$("$(setup_bin copilot-marketplace)" add "$repository" 2>&1)"; then
                SETUP_MESSAGE="$output"
                return 1
            fi
            SETUP_MESSAGE="registered $name from $repository"
            ;;
        uvTool)
            name="$(jq -r '.name' <<< "$resource")"
            if ! output="$("$(setup_bin uv-tool)" install "$name" 2>&1)"; then
                SETUP_MESSAGE="$output"
                return 1
            fi
            # shellcheck disable=SC2034  # result message is consumed by the sourcing command
            SETUP_MESSAGE="installed $name"
            ;;
    esac
}

setup_action_description() {
    local resource="$1" type
    type="$(jq -r '.type' <<< "$resource")"
    case "$type" in
        symlink)
            printf 'create symlink %s -> %s\n' \
                "$(jq -r '.path' <<< "$resource")" "$(jq -r '.target' <<< "$resource")"
            ;;
        copilotPlugin) printf 'install Copilot plugin %s\n' "$(jq -r '.source' <<< "$resource")" ;;
        copilotMarketplace) printf 'add Copilot marketplace %s\n' "$(jq -r '.repository' <<< "$resource")" ;;
        uvTool) printf 'install uv tool %s\n' "$(jq -r '.name' <<< "$resource")" ;;
    esac
}

make_setup_result() {
    local index="$1" type="$2" name="$3" status="$4"
    local satisfied="$5" changed="$6" message="$7"
    jq -cn \
        --argjson index "$index" --arg type "$type" --arg name "$name" \
        --arg status "$status" --argjson satisfied "$satisfied" \
        --argjson changed "$changed" --arg message "$message" \
        '{index:$index,type:$type,name:$name,status:$status,
          satisfied:$satisfied,changed:$changed,message:$message}'
}
