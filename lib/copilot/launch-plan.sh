#!/usr/bin/env bash
# launch-plan.sh — build the Copilot CLI launch plan (ported from
# Get-CopilotLaunchPlan). Populates globals used by start-copilot and
# copilot-launch-plan:
#   COPILOT_EXE          resolved copilot executable
#   COPILOT_ARGS         array of arguments
#   COPILOT_PASSTHROUGH  1 when the prompt is a passthrough command (update/help)
#
# Source lib/common.sh and lib/copilot/copilot-common.sh first.

if [[ -n "${_SHM_COPILOT_LAUNCHPLAN_SOURCED:-}" ]]; then
    return 0
fi
_SHM_COPILOT_LAUNCHPLAN_SOURCED=1

# Auto-generated maintenance session names to skip when auto-resuming.
# Ported verbatim from Get-CopilotLaunchPlan.ps1.
_SHM_IGNORED_SESSION_NAMES=(
    'Apply context_board add/prune updates for this session. End the turn with a 2-3 sentence summary of the changes you made to the context_board.'
    'Analyze the session file and write the session insights result to the specified output file as described in the instructions.'
    'Session File Path:'
)

# The destructive-git deny-tool set. --deny-tool takes precedence over --allow-all.
_SHM_DENY_TOOLS=(
    'shell(git push --force)'
    'shell(git push -f)'
    'shell(git push --force-with-lease)'
    'shell(git checkout --force)'
    'shell(git checkout -f)'
    'shell(git clean --force)'
    'shell(git clean -f)'
    'shell(git reset --hard)'
    'shell(git commit --amend)'
    'shell(git commit -a --amend)'
    'shell(git rebase)'
    'shell(git rebase -i)'
    'shell(git rebase --interactive)'
    'shell(git pull)'
)

_launch_plan_usage() {
    cat <<'EOF'
Usage: start-copilot [options] [prompt] [-- copilot-args...]

Wraps the copilot CLI with automatic session resume, default permissions,
destructive-git deny rules, and MCP autoConnect policy.

Resume control:
  --no-resume              Start a new session; never resume.
  --resume-latest          With multiple sessions, resume the most recent.
  --resume-session <id>    Resume a specific session (id, id-prefix, or name).
  --no-auto-resume         Force the session picker whenever any session exists.
  --include-unnamed        Include unnamed '(no summary)' sessions in the picker.
  --defer-resume           Emit no --resume and skip the picker (for overlays).

Defaults (each disablable):
  --no-allow-all           Do not pass --allow-all.
  --no-experimental        Do not pass --experimental.
  --no-default-deny-tools  Do not add the destructive-git deny rules.

MCP:
  --enable-mcp-server <n>  Force a server on regardless of its autoConnect policy.
  --disable-mcp-server <n> Force a server off for this launch.

Convenience passthrough (forwarded to copilot):
  --model, --reasoning-effort, --agent, --mode, --context, --add-dir,
  --log-level, --output-format, --session-id, --name, -C/--change-dir, --plan.

Any other copilot flags: place them after `--`.
A single bare argument is the autopilot prompt; `update`/`help` pass straight through.
EOF
}

# _shm_is_ignored_name NAME — return 0 if NAME is an ignored maintenance name.
_shm_is_ignored_name() {
    local n="$1" ign
    for ign in "${_SHM_IGNORED_SESSION_NAMES[@]}"; do
        [[ "$n" == "$ign" ]] && return 0
    done
    return 1
}

# _shm_resolve_resume — decide which session to resume and echo its id (or nothing).
# Uses the parsed resume flags in the caller's scope.
_shm_resolve_resume() {
    local resume_latest="$1" show_picker="$2" include_unnamed="$3"
    local cwd branch
    cwd="$(pwd -P)"
    branch="$(copilot_current_branch)"

    # Collect cwd-filtered sessions (newest first), dropping ignored/undated ones.
    local ids=() names=() branches=()
    local id display s_cwd s_branch s_repo created updated ecount esize path
    # shellcheck disable=SC2034  # unpacking a fixed row; not all fields used here
    while IFS="$SHM_FS" read -r id display s_cwd s_branch s_repo created updated ecount esize path; do
        [[ -z "$updated" ]] && continue
        _shm_is_ignored_name "$display" && continue
        ids+=("$id"); names+=("$display"); branches+=("$s_branch")
    done < <(copilot_sessions)

    local count=${#ids[@]}
    [[ "$count" -eq 0 ]] && return 0

    # Prefer sessions matching the current git branch, if any match.
    if [[ -n "$branch" ]]; then
        local m_ids=() m_names=() m_branches=() i
        for i in "${!ids[@]}"; do
            if [[ "${branches[$i]}" == "$branch" ]]; then
                m_ids+=("${ids[$i]}"); m_names+=("${names[$i]}"); m_branches+=("${branches[$i]}")
            fi
        done
        if [[ ${#m_ids[@]} -gt 0 ]]; then
            ids=("${m_ids[@]}"); names=("${m_names[@]}"); branches=("${m_branches[@]}")
        fi
    fi
    count=${#ids[@]}

    # Named sessions: real display name (not blank, not the placeholder).
    local named_ids=() named_names=() i
    for i in "${!ids[@]}"; do
        local nm="${names[$i]}"
        if [[ -n "${nm// /}" && "$nm" != '(no summary)' ]]; then
            named_ids+=("${ids[$i]}"); named_names+=("$nm")
        fi
    done

    # Picker candidate set: hide unnamed stubs when named sessions exist.
    # shellcheck disable=SC2034  # populated for nameref use by _shm_session_picker
    local pick_ids=() pick_names=()
    if [[ "$include_unnamed" == "0" && ${#named_ids[@]} -gt 0 ]]; then
        pick_ids=("${named_ids[@]}"); pick_names=("${named_names[@]}")
    else
        # shellcheck disable=SC2034
        pick_ids=("${ids[@]}")
        # shellcheck disable=SC2034
        pick_names=("${names[@]}")
    fi

    if [[ "$show_picker" == "1" && "$count" -ge 1 ]]; then
        _shm_session_picker pick_ids pick_names
    elif [[ "$count" -eq 1 ]]; then
        printf '%s\n' "${ids[0]}"
    elif [[ "$count" -gt 1 && "$resume_latest" == "1" ]]; then
        printf '%s\n' "${ids[0]}"
    elif [[ "$count" -gt 1 && ${#named_ids[@]} -eq 1 ]]; then
        printf '%s\n' "${named_ids[0]}"
    elif [[ "$count" -gt 1 ]]; then
        _shm_session_picker pick_ids pick_names
    fi
}

# _shm_session_picker IDS_ARRAY NAMES_ARRAY — show a picker and echo the chosen id
# (empty for "New session"). Uses fzf/select via pick_one on labels.
_shm_session_picker() {
    local -n _ids="$1"; local -n _names="$2"
    local labels=() i
    for i in "${!_ids[@]}"; do
        labels+=("$((i + 1))) ${_names[$i]}  [${_ids[$i]:0:8}]")
    done
    labels+=("N) New session")
    local choice
    choice="$(printf '%s\n' "${labels[@]}" | pick_one 'Session')" || return 0
    [[ -z "$choice" || "$choice" == 'N) New session' ]] && return 0
    # Map the chosen label back to its index.
    for i in "${!labels[@]}"; do
        if [[ "${labels[$i]}" == "$choice" ]]; then
            [[ "$i" -lt "${#_ids[@]}" ]] && printf '%s\n' "${_ids[$i]}"
            return 0
        fi
    done
}

# build_launch_plan ARGS... — parse arguments and populate COPILOT_EXE/ARGS/PASSTHROUGH.
build_launch_plan() {
    # These globals are consumed by start-copilot and copilot-launch-plan.
    # shellcheck disable=SC2034
    COPILOT_EXE="$(resolve_copilot)"
    COPILOT_ARGS=()
    # shellcheck disable=SC2034
    COPILOT_PASSTHROUGH=0

    local prompt='' name=''
    local no_resume=0 resume_latest=0 resume_session='' show_picker=0 include_unnamed=0 defer_resume=0
    local session_id_present=0
    local no_allow_all=0 no_experimental=0 no_deny=0
    local enable_mcp=() disable_mcp=() fwd=() passthrough_args=() saw_ddash=0

    while [[ $# -gt 0 ]]; do
        if [[ "$saw_ddash" == "1" ]]; then
            [[ "$1" == '--session-id' || "$1" == --session-id=* ]] && session_id_present=1
            passthrough_args+=("$1"); shift; continue
        fi
        case "$1" in
            --) saw_ddash=1; shift ;;
            --no-resume) no_resume=1; shift ;;
            --resume-latest) resume_latest=1; shift ;;
            --resume-session) resume_session="$2"; shift 2 ;;
            --no-auto-resume|--show-picker) show_picker=1; shift ;;
            --include-unnamed) include_unnamed=1; shift ;;
            --defer-resume) defer_resume=1; shift ;;
            --no-allow-all) no_allow_all=1; shift ;;
            --no-experimental) no_experimental=1; shift ;;
            --no-default-deny-tools) no_deny=1; shift ;;
            --enable-mcp-server) enable_mcp+=("$2"); shift 2 ;;
            --disable-mcp-server) disable_mcp+=("$2"); shift 2 ;;
            --name) name="$2"; shift 2 ;;
            --session-id)
                session_id_present=1
                fwd+=("$1" "$2"); shift 2 ;;
            --session-id=*)
                session_id_present=1
                fwd+=("$1"); shift ;;
            --model|--reasoning-effort|--agent|--mode|--context|--add-dir|--log-level|--output-format|-C|--change-dir)
                fwd+=("$1" "$2"); shift 2 ;;
            --plan) fwd+=("$1"); shift ;;
            -h|--help) _launch_plan_usage; return 2 ;;
            -*) fwd+=("$1"); shift ;;
            *) if [[ -z "$prompt" ]]; then prompt="$1"; else fwd+=("$1"); fi; shift ;;
        esac
    done

    # Passthrough commands (update/help) bypass the built args entirely.
    if [[ "$prompt" == "update" || "$prompt" == "help" ]]; then
        # shellcheck disable=SC2034
        COPILOT_PASSTHROUGH=1
        COPILOT_ARGS=("$prompt")
        [[ ${#fwd[@]} -gt 0 ]] && COPILOT_ARGS+=("${fwd[@]}")
        [[ ${#passthrough_args[@]} -gt 0 ]] && COPILOT_ARGS+=("${passthrough_args[@]}")
        return 0
    fi

    # Defaults.
    [[ "$no_experimental" == "0" ]] && COPILOT_ARGS+=(--experimental)
    [[ "$no_allow_all" == "0" ]] && COPILOT_ARGS+=(--allow-all)

    # Destructive-git deny rules.
    if [[ "$no_deny" == "0" ]]; then
        local t
        for t in "${_SHM_DENY_TOOLS[@]}"; do
            COPILOT_ARGS+=(--deny-tool "$t")
        done
    fi

    # MCP autoConnect policy (path-glob arrays only; boolean false is native lazy).
    _shm_apply_mcp_autoconnect enable_mcp disable_mcp

    # Forwarded convenience/unknown flags.
    [[ ${#fwd[@]} -gt 0 ]] && COPILOT_ARGS+=("${fwd[@]}")

    # Resume decision.
    local resumed=0
    if [[ -n "$resume_session" ]]; then
        log_verbose "Resuming session: $resume_session"
        COPILOT_ARGS+=(--resume "$resume_session"); resumed=1
    elif [[ "$no_resume" == "0" && "$defer_resume" == "0" && "$session_id_present" == "0" ]]; then
        local chosen
        chosen="$(_shm_resolve_resume "$resume_latest" "$show_picker" "$include_unnamed")"
        if [[ -n "$chosen" ]]; then
            log_verbose "Resuming session: $chosen"
            COPILOT_ARGS+=(--resume "$chosen"); resumed=1
        fi
    fi

    # -Name applies only to new (non-resumed) sessions.
    if [[ -n "$name" && "$resumed" == "0" ]]; then
        COPILOT_ARGS+=(--name "$name")
    fi

    # Prompt -> autopilot; otherwise interactive.
    if [[ -n "$prompt" ]]; then
        COPILOT_ARGS+=(--autopilot -p "$prompt")
    fi

    # Arbitrary passthrough args (after --).
    [[ ${#passthrough_args[@]} -gt 0 ]] && COPILOT_ARGS+=("${passthrough_args[@]}")
    return 0
}

# _shm_apply_mcp_autoconnect ENABLE_ARRAY DISABLE_ARRAY — append --disable-mcp-server
# flags per the autoConnect glob policy, then per explicit --disable-mcp-server.
_shm_apply_mcp_autoconnect() {
    local -n _enable="$1"; local -n _disable="$2"
    local cfg; cfg="$(copilot_home)/mcp-config.json"
    local cwd; cwd="$(pwd -P)"

    if [[ -f "$cfg" ]] && have_cmd jq; then
        declare -A in_enable=()
        local e
        for e in "${_enable[@]}"; do in_enable["$e"]=1; done

        declare -A has_glob=() matched=()
        local sname glob
        while IFS=$'\t' read -r sname glob; do
            [[ -z "$sname" ]] && continue
            [[ -n "${in_enable[$sname]:-}" ]] && continue
            has_glob["$sname"]=1
            # shellcheck disable=SC2053  # intentional glob match, mirrors PowerShell -like
            [[ "$cwd" == $glob ]] && matched["$sname"]=1
        done < <(jq -r '.mcpServers // {} | to_entries[]
            | select((.value.autoConnect | type) == "array")
            | .key as $k | .value.autoConnect[] | "\($k)\t\(.)"' "$cfg" 2>/dev/null)

        for sname in "${!has_glob[@]}"; do
            [[ -z "${matched[$sname]:-}" ]] && COPILOT_ARGS+=(--disable-mcp-server "$sname")
        done
    fi

    local s
    for s in "${_disable[@]}"; do
        COPILOT_ARGS+=(--disable-mcp-server "$s")
    done
}
