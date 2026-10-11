#!/usr/bin/env bash
# Value-only selector protocol shared by session selection and launch planning.
# Source common.sh and copilot-common.sh first.

copilot_rows_json() {
    require_cmd jq
    jq -R -s 'def nz: if .=="" then null else . end;
        split("\n") | map(select(length>0) | split("\u001f") |
        {id:.[0], name:.[1], cwd:(.[2]|nz), branch:(.[3]|nz),
         repository:(.[4]|nz), createdAt:(.[5]|nz), updatedAt:(.[6]|nz),
         eventCount:(.[7]|tonumber), eventSize:(.[8]|tonumber), path:.[9]})'
}

# Emit the original candidate ID, nothing for new, or status 130 for cancel.
# The selector is one executable, never a shell command string.
copilot_select_callback() {
    local selector="$1" result decision row id
    local -n _candidate_rows="$2"
    [[ ${#_candidate_rows[@]} -gt 0 ]] || return 0
    require_cmd jq
    if ! result="$(printf '%s\n' "${_candidate_rows[@]}" | copilot_rows_json | "$selector")"; then
        log_error "Copilot selector failed: $selector"
        return 1
    fi
    if ! decision="$(printf '%s' "$result" | jq -er -s '
        if length != 1 then error("expected one result") else .[0] end |
        if type != "object" then error("expected an object")
        elif (.id | type) == "string" and (.id | length) > 0 and (has("action") | not)
            then "id:" + .id
        elif (has("id") | not) and (.action == "new" or .action == "cancel")
            then "action:" + .action
        else error("expected id or new/cancel action") end' 2>/dev/null)"; then
        log_error 'Invalid Copilot selector result: expected {"id":"candidate-id"}, {"action":"new"}, or {"action":"cancel"}.'
        return 1
    fi
    case "$decision" in
        action:new) return 0 ;;
        action:cancel) log_verbose 'Copilot selection cancelled.'; return 130 ;;
        id:*)
            id="${decision#id:}"
            for row in "${_candidate_rows[@]}"; do
                if [[ "${row%%"$SHM_FS"*}" == "$id" ]]; then
                    printf '%s\n' "$id"
                    return 0
                fi
            done
            log_error "Copilot selector returned an ID outside the candidate set: $id"
            return 1 ;;
    esac
}

# One shared native picker; each shortcut maps to an original row, never a label.
copilot_paginated_picker() {
    local -n _page_rows="$1"
    [[ ${#_page_rows[@]} -gt 0 ]] || return 0
    require_cmd node
    require_cmd jq
    local presentation
    presentation="$(printf '%s\n' "${_page_rows[@]}" | copilot_rows_json |
        node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-display.js")" || return 1
    local -a display_labels=()
    mapfile -t display_labels < <(printf '%s' "$presentation" | jq -r '.[].label')
    local keys='ABDEFGHIJKLOQRSTUVWXYZ' page_start=0 count=${#_page_rows[@]} page_size=22
    local tty="${SHM_TTY_PATH:-/dev/tty}" tty_fd='' use_fzf=0
    if [[ -z "${SHM_TTY_PATH:-}" ]] && have_cmd fzf; then
        use_fzf=1
    elif ! { exec {tty_fd}<"$tty"; } 2>/dev/null; then
        log_error 'Session selection requires console input or --selector.'
        return 1
    fi
    local page_end i choice key matched status context
    local -a choices=()
    while :; do
        page_end=$((page_start + page_size))
        [[ "$page_end" -le "$count" ]] || page_end="$count"
        choices=()
        for ((i = page_start; i < page_end; i++)); do
            choices+=("${keys:i-page_start:1} - ${display_labels[i]}")
        done
        [[ "$page_start" -eq 0 ]] || choices+=('P - Previous page')
        [[ "$page_end" -ge "$count" ]] || choices+=('M - Next page')
        choices+=('N - New session' 'C - Cancel' '? - Full session details')
        context="Sessions $((page_start + 1))-$page_end of $count (page $((page_start / page_size + 1)) of $(((count + page_size - 1) / page_size))). No default selection."
        if [[ "$use_fzf" == "1" ]]; then
            local details
            details="$(printf '%s' "$presentation" | jq -r --argjson start "$page_start" --argjson stop "$page_end" \
                '.[$start:$stop] | map(.help) | join("\n\n")')" || return 1
            status=0
            choice="$(printf '%s\n' "${choices[@]}" |
                fzf --prompt='Session> ' --height=40% --reverse --bind=start:last \
                    --header="$context"$'\n\n'"$details")" || status=$?
            if [[ "$status" -ne 0 ]]; then
                [[ "$status" -eq 130 ]] || log_error 'No Copilot session selected.'
                return "$status"
            fi
            matched=0
            for key in "${choices[@]}"; do [[ "$key" != "$choice" ]] || matched=1; done
            if [[ "$matched" == "0" ]]; then
                log_error 'Invalid Copilot session selection.'
                return 1
            fi
            choice="${choice:0:1}"
        else
            printf '\n%s\n' "$context" >&2
            printf '%s\n' "${choices[@]}" >&2
            printf 'Session key (? or ?A for details): ' >&2
            if ! IFS= read -r -u "$tty_fd" choice; then
                exec {tty_fd}<&-
                log_error 'No Copilot session selected.'
                return 1
            fi
            choice="$(_workspace_yaml_trim "$choice")"
            choice="${choice^^}"
        fi
        case "$choice" in
            N) [[ -z "$tty_fd" ]] || exec {tty_fd}<&-; return 0 ;;
            C) [[ -z "$tty_fd" ]] || exec {tty_fd}<&-; return 130 ;;
            M) [[ "$page_end" -ge "$count" ]] || page_start="$page_end"; continue ;;
            P) [[ "$page_start" -eq 0 ]] || page_start=$((page_start - page_size)); continue ;;
            \?*)
                key="${choice#?}"
                for ((i = page_start; i < page_end; i++)); do
                    if [[ -z "$key" || "$key" == "${keys:i-page_start:1}" ]]; then
                        printf '%s' "$presentation" | jq -r --argjson index "$i" '.[$index].help' >&2
                    fi
                done
                continue ;;
        esac
        for ((i = page_start; i < page_end; i++)); do
            if [[ "$choice" == "${keys:i-page_start:1}" ]]; then
                [[ -z "$tty_fd" ]] || exec {tty_fd}<&-
                printf '%s\n' "${_page_rows[i]%%"$SHM_FS"*}"
                return 0
            fi
        done
        log_warn 'Choose a displayed session key or action; there is no default.'
    done
}
