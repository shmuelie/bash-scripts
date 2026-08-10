#!/usr/bin/env bash
# copilot-common.sh — shared helpers ported from Shmuelie.Copilot.
#
# Session enumeration (from ~/.copilot/session-state workspace.yaml), display-name
# parsing (handling YAML block scalars), and the copilot executable resolver.
# Source lib/common.sh first.

if [[ -n "${_SHM_COPILOT_COMMON_SOURCED:-}" ]]; then
    return 0
fi
_SHM_COPILOT_COMMON_SOURCED=1

# Field separator for internal structured rows. A non-whitespace character (US,
# 0x1f) is used instead of TAB so `IFS=... read` preserves empty middle fields
# (with a whitespace IFS like TAB, runs of the delimiter collapse and shift
# columns). jq consumers split on "\u001f".
SHM_FS=$'\x1f'

# copilot_home — the ~/.copilot root. Overridable with COPILOT_HOME for testing.
copilot_home() {
    printf '%s\n' "${COPILOT_HOME:-$HOME/.copilot}"
}

# copilot_session_state_dir — the session-state directory.
copilot_session_state_dir() {
    printf '%s/session-state\n' "$(copilot_home)"
}

# resolve_copilot — print the path to the copilot executable, or die.
resolve_copilot() {
    local exe
    exe="$(command -v copilot 2>/dev/null)" || die 'copilot executable not found on PATH.'
    printf '%s\n' "$exe"
}

# copilot_ws_field FILE KEY — print the value of a simple `key: value` line.
copilot_ws_field() {
    local file="$1" key="$2"
    sed -n "s/^${key}:[[:space:]]*\(.*\)$/\1/p" "$file" | head -n1 |
        sed -e 's/[[:space:]]*$//'
}

# copilot_ws_name FILE — print the session name, handling YAML block scalars
# (`name: |-` / `>-` followed by an indented line) and plain `name: value`.
# Ported from the name-parsing logic in Sessions.ps1 / Get-CopilotLaunchPlan.ps1.
copilot_ws_name() {
    local file="$1"
    awk '
        /^name:[[:space:]]*[|>]-?[[:space:]]*$/ { block=1; next }
        block==1 {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
            exit
        }
        /^name:[[:space:]]+/ {
            line=$0
            sub(/^name:[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
            exit
        }
    ' "$file"
}

# copilot_display_name FILE — name, else summary, else "(no summary)".
copilot_display_name() {
    local file="$1" name summary
    name="$(copilot_ws_name "$file")"
    if [[ -n "$name" ]]; then printf '%s\n' "$name"; return; fi
    summary="$(copilot_ws_field "$file" summary)"
    if [[ -n "$summary" ]]; then printf '%s\n' "$summary"; return; fi
    printf '%s\n' '(no summary)'
}

# copilot_sessions [--all] [--id ID] — emit one TSV row per session, newest first:
#   id  display  cwd  branch  repository  created  updated  eventCount  eventSize  path
# Ported from Get-CopilotSession. Without --all or --id, filters to the current cwd.
copilot_sessions() {
    local all=0 only_id='' cwd
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) all=1; shift ;;
            --id) only_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local state_dir; state_dir="$(copilot_session_state_dir)"
    [[ -d "$state_dir" ]] || return 0
    cwd="$(pwd -P)"

    local dir ws
    local rows=()
    for dir in "$state_dir"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        local id; id="$(basename -- "$dir")"
        [[ -n "$only_id" && "$id" != "$only_id" ]] && continue
        ws="$dir/workspace.yaml"
        [[ -f "$ws" ]] || continue

        local s_cwd s_updated s_created s_branch s_repo display
        s_cwd="$(copilot_ws_field "$ws" cwd)"
        s_updated="$(copilot_ws_field "$ws" updated_at)"
        s_created="$(copilot_ws_field "$ws" created_at)"
        s_branch="$(copilot_ws_field "$ws" branch)"
        s_repo="$(copilot_ws_field "$ws" repository)"
        display="$(copilot_display_name "$ws")"

        if [[ "$all" == "0" && -z "$only_id" && "$s_cwd" != "$cwd" ]]; then
            continue
        fi

        local events="$dir/events.jsonl" ecount=0 esize=0
        if [[ -f "$events" ]]; then
            ecount="$(wc -l < "$events" | tr -d ' ')"
            esize="$(stat -c '%s' "$events" 2>/dev/null || stat -f '%z' "$events" 2>/dev/null || echo 0)"
        fi

        rows+=("$s_updated$SHM_FS$id$SHM_FS$display$SHM_FS$s_cwd$SHM_FS$s_branch$SHM_FS$s_repo$SHM_FS$s_created$SHM_FS$s_updated$SHM_FS$ecount$SHM_FS$esize$SHM_FS$dir")
    done

    [[ ${#rows[@]} -eq 0 ]] && return 0
    # Sort by leading updated_at descending, then drop the sort key.
    printf '%s\n' "${rows[@]}" | sort -r -t"$SHM_FS" -k1,1 | cut -d"$SHM_FS" -f2-
}

# copilot_current_branch — best-effort current git branch, or empty.
copilot_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || true
}
