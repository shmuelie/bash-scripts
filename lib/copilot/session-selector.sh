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
