#!/usr/bin/env bash
# launch-plan.sh — build the Copilot CLI launch plan (ported from
# Get-CopilotLaunchPlan). Populates globals used by start-copilot and
# copilot-launch-plan:
#   COPILOT_EXE          resolved copilot executable
#   COPILOT_ARGS         array of arguments
#   COPILOT_PASSTHROUGH  1 when the prompt is a passthrough command (update/help)
#   COPILOT_CWD          absolute effective planning/native directory
#
# Source lib/common.sh and lib/copilot/copilot-common.sh first.

if [[ -n "${_SHM_COPILOT_LAUNCHPLAN_SOURCED:-}" ]]; then
    return 0
fi
_SHM_COPILOT_LAUNCHPLAN_SOURCED=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-selector.sh"

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
  --selector <executable>  Replace only the picker using the JSON selector protocol.

Defaults (each disablable):
  --no-allow-all           Do not pass --allow-all.
  --no-experimental        Do not pass --experimental.
  --no-default-deny-tools  Do not add the destructive-git deny rules.

Approval and output:
  --assisted-approval       Use assisted approval (requires experimental mode).
  --allow-all-tools         Allow tools while retaining path/URL verification.
  --usage-output-file <p>   Write native usage output to the specified path.

Routing and initial prompt:
  --prompt/-p <text>        Non-interactive autopilot prompt (also a bare argument).
  --interactive/-i <text>  Initial prompt that remains interactive.
  --fleet                  Fleet mode; requires a prompt or --interactive.
  --auto-tier <tier>        efficiency, balance, or intelligence; model must be auto.
  --dynamic-retrieval <setting>  skills=on or skills=off (repeatable; CLI persists it).
  --mouse <on|off>          Native mouse setting.
  --no-mouse               Native no-mouse switch; cannot combine with --mouse.
  --remote                 Request remote control; requires one GitHub origin.
  --no-remote              Keep the session local (takes precedence).

MCP:
  --enable-mcp-server <n>  Force a server on and forward the native enable flag.
  --disable-mcp-server <n> Force a server off for this launch.
  --additional-mcp-config <JSON|@path>  Explicit remote configuration (repeatable).
  --mcp-github-auth <server=origin>     Scoped native GitHub auth (repeatable).
    Requires a named explicit HTTP/SSE server at the approved HTTPS origin.
    HTTP is allowed only for literal 127.0.0.1 or [::1]. Never include credentials.
    Plans do not authenticate; explicit config remains verbatim in returned plans.

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
    local resume_latest="$1" show_picker="$2" include_unnamed="$3" selector="$4"
    local _SCOPE_CWD _SCOPE_REPOSITORY _SCOPE_BRANCH
    copilot_session_scope

    # Collect scoped sessions (newest first), dropping ignored/undated ones.
    local ids=() names=() branches=() candidate_rows=() sessions_out
    sessions_out="$(copilot_sessions)" || return 1
    local id display s_cwd s_branch s_repo created updated ecount esize path
    # shellcheck disable=SC2034  # unpacking a fixed row; not all fields used here
    while IFS="$SHM_FS" read -r id display s_cwd s_branch s_repo created updated ecount esize path; do
        [[ -z "$updated" ]] && continue
        _shm_is_ignored_name "$display" && continue
        ids+=("$id"); names+=("$display"); branches+=("$s_branch")
        candidate_rows+=("$id$SHM_FS$display$SHM_FS$s_cwd$SHM_FS$s_branch$SHM_FS$s_repo$SHM_FS$created$SHM_FS$updated$SHM_FS$ecount$SHM_FS$esize$SHM_FS$path")
    done <<<"$sessions_out"

    local count=${#ids[@]}
    [[ "$count" -eq 0 ]] && return 0

    # Prefer complete origin/branch matches over directory-only legacy sessions.
    if [[ -n "$_SCOPE_REPOSITORY" && -n "$_SCOPE_BRANCH" ]]; then
        local identity_rows=() identity_ids=() identity_names=() identity_branches=() i
        for i in "${!ids[@]}"; do
            IFS="$SHM_FS" read -r id display s_cwd s_branch s_repo created updated ecount esize path <<<"${candidate_rows[i]}"
            if [[ -n "$s_repo" && "${s_repo,,}" == "${_SCOPE_REPOSITORY,,}" ]] &&
               test "$s_branch" = "$_SCOPE_BRANCH"; then
                identity_ids+=("${ids[i]}"); identity_names+=("${names[i]}")
                identity_branches+=("${branches[i]}"); identity_rows+=("${candidate_rows[i]}")
            fi
        done
        if [[ ${#identity_ids[@]} -gt 0 ]]; then
            ids=("${identity_ids[@]}"); names=("${identity_names[@]}")
            branches=("${identity_branches[@]}"); candidate_rows=("${identity_rows[@]}")
        fi
    fi

    # Retain branch preference for incomplete directory-only metadata.
    if [[ -n "$_SCOPE_BRANCH" ]]; then
        local m_ids=() m_names=() m_branches=() m_rows=() i
        for i in "${!ids[@]}"; do
            if test "${branches[$i]}" = "$_SCOPE_BRANCH"; then
                m_ids+=("${ids[$i]}"); m_names+=("${names[$i]}"); m_branches+=("${branches[$i]}")
                m_rows+=("${candidate_rows[$i]}")
            fi
        done
        if [[ ${#m_ids[@]} -gt 0 ]]; then
            ids=("${m_ids[@]}"); names=("${m_names[@]}"); branches=("${m_branches[@]}")
            candidate_rows=("${m_rows[@]}")
        fi
    fi
    count=${#ids[@]}

    # Named sessions: real display name (not blank, not the placeholder).
    local named_ids=() named_names=() named_rows=() i
    for i in "${!ids[@]}"; do
        local nm="${names[$i]}"
        if [[ -n "${nm// /}" && "$nm" != '(no summary)' ]]; then
            named_ids+=("${ids[$i]}"); named_names+=("$nm")
            named_rows+=("${candidate_rows[$i]}")
        fi
    done

    # Picker candidate set: hide unnamed stubs when named sessions exist.
    # shellcheck disable=SC2034  # populated for nameref use by _shm_session_picker
    local pick_ids=() pick_names=() pick_rows=()
    if [[ "$include_unnamed" == "0" && ${#named_ids[@]} -gt 0 ]]; then
        pick_ids=("${named_ids[@]}"); pick_names=("${named_names[@]}")
        pick_rows=("${named_rows[@]}")
    else
        # shellcheck disable=SC2034
        pick_ids=("${ids[@]}")
        # shellcheck disable=SC2034
        pick_names=("${names[@]}")
        # shellcheck disable=SC2034  # consumed through the selector's nameref
        pick_rows=("${candidate_rows[@]}")
    fi

    if [[ "$show_picker" == "1" && "$count" -ge 1 ]]; then
        _shm_session_picker pick_ids pick_names pick_rows "$selector"
    elif [[ "$count" -eq 1 ]]; then
        printf '%s\n' "${ids[0]}"
    elif [[ "$count" -gt 1 && "$resume_latest" == "1" ]]; then
        printf '%s\n' "${ids[0]}"
    elif [[ "$count" -gt 1 && ${#named_ids[@]} -eq 1 ]]; then
        printf '%s\n' "${named_ids[0]}"
    elif [[ "$count" -gt 1 ]]; then
        _shm_session_picker pick_ids pick_names pick_rows "$selector"
    fi
}

# _shm_session_picker IDS_ARRAY NAMES_ARRAY ROWS_ARRAY SELECTOR — value-only picker.
_shm_session_picker() {
    if [[ -n "$4" ]]; then
        copilot_select_callback "$4" "$3"
        return $?
    fi
    copilot_paginated_picker "$3"
}

# build_launch_plan ARGS... — parse arguments and populate COPILOT_EXE/ARGS/PASSTHROUGH.
build_launch_plan() {
    # These globals are consumed by start-copilot and copilot-launch-plan.
    # shellcheck disable=SC2034
    COPILOT_EXE=''
    COPILOT_ARGS=()
    # shellcheck disable=SC2034
    COPILOT_PASSTHROUGH=0

    local prompt='' name='' selector='' interactive='' change_dir='' change_index=-1
    local no_resume=0 resume_latest=0 resume_session='' show_picker=0 include_unnamed=0 defer_resume=0
    local session_id_present=0
    local no_allow_all=0 no_experimental=0 no_deny=0
    local assisted_approval=0
    local additional_mcp=() mcp_github_auth=()
    local fleet=0 auto_tier='' model='' no_mouse=0 mouse_present=0 no_eager_powershell=0 prefer_version=0
    local enable_mcp=() disable_mcp=() fwd=() passthrough_args=() change_indices=() saw_ddash=0

    while [[ $# -gt 0 ]]; do
        if [[ "$saw_ddash" == "1" ]]; then
            [[ "$1" == '--session-id' || "$1" == --session-id=* ]] && session_id_present=1
            passthrough_args+=("$1"); shift; continue
        fi
        case "$1" in
            --auto-tier=*|--dynamic-retrieval=*|--mouse=*|--prefer-version=*|--interactive=*|--prompt=*|--model=*)
                set -- "${1%%=*}" "${1#*=}" "${@:2}" ;;
        esac
        case "$1" in
            --) saw_ddash=1; shift ;;
            --no-resume) no_resume=1; shift ;;
            --resume-latest) resume_latest=1; shift ;;
            --resume-session) resume_session="$2"; shift 2 ;;
            --no-auto-resume|--show-picker) show_picker=1; shift ;;
            --include-unnamed) include_unnamed=1; shift ;;
            --defer-resume) defer_resume=1; shift ;;
            --selector)
                [[ $# -ge 2 && -n "$2" ]] || die '--selector requires an executable.'
                selector="$2"; shift 2 ;;
            --no-allow-all) no_allow_all=1; shift ;;
            --no-experimental) no_experimental=1; shift ;;
            --no-default-deny-tools) no_deny=1; shift ;;
            --assisted-approval)
                assisted_approval=1
                fwd+=("$1")
                shift ;;
            --allow-all-tools)
                no_allow_all=1
                fwd+=("$1")
                shift ;;
            --usage-output-file)
                [[ $# -ge 2 ]] || die '--usage-output-file requires a path.'
                fwd+=("$1" "$2")
                shift 2 ;;
            --enable-mcp-server)
                [[ $# -ge 2 ]] || die '--enable-mcp-server requires a server name.'
                enable_mcp+=("$2")
                fwd+=("$1" "$2")
                shift 2 ;;
            --disable-mcp-server)
                [[ $# -ge 2 ]] || die '--disable-mcp-server requires a server name.'
                disable_mcp+=("$2"); shift 2 ;;
            --additional-mcp-config)
                [[ $# -ge 2 && -n "$2" ]] || die '--additional-mcp-config requires JSON or @path.'
                additional_mcp+=("$2"); fwd+=("$1" "$2"); shift 2 ;;
            --additional-mcp-config=*)
                additional_mcp+=("${1#*=}"); fwd+=(--additional-mcp-config "${1#*=}"); shift ;;
            --mcp-github-auth)
                [[ $# -ge 2 && -n "$2" ]] || die '--mcp-github-auth requires server=origin.'
                mcp_github_auth+=("$2"); fwd+=("$1" "$2"); shift 2 ;;
            --mcp-github-auth=*)
                mcp_github_auth+=("${1#*=}"); fwd+=(--mcp-github-auth "${1#*=}"); shift ;;
            --name)
                [[ $# -ge 2 ]] || die '--name requires a value.'
                name="$2"; shift 2 ;;
            --prompt|-p)
                [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a prompt."
                prompt="$2"; shift 2 ;;
            --interactive|-i)
                [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a prompt."
                interactive="$2"; fwd+=(--interactive "$2"); shift 2 ;;
            --fleet) fleet=1; fwd+=("$1"); shift ;;
            --auto-tier)
                [[ $# -ge 2 ]] || die '--auto-tier requires efficiency, balance, or intelligence.'
                case "$2" in efficiency|balance|intelligence) ;; *) die 'Invalid --auto-tier: use efficiency, balance, or intelligence.' ;; esac
                auto_tier="$2"; fwd+=("$1" "$2"); shift 2 ;;
            --dynamic-retrieval)
                [[ $# -ge 2 ]] || die '--dynamic-retrieval requires skills=on or skills=off.'
                case "$2" in skills=on|skills=off) ;; *) die 'Invalid --dynamic-retrieval: use skills=on or skills=off.' ;; esac
                fwd+=("$1" "$2"); shift 2 ;;
            --mouse)
                [[ $# -ge 2 ]] || die '--mouse requires on or off.'
                case "$2" in on|off) ;; *) die 'Invalid --mouse: use on or off.' ;; esac
                mouse_present=1; fwd+=("$1" "$2"); shift 2 ;;
            --no-mouse) no_mouse=1; fwd+=("$1"); shift ;;
            --no-eager-powershell-resolution)
                no_eager_powershell=1; fwd+=("$1"); shift ;;
            --prefer-version)
                [[ $# -ge 2 && -n "$2" ]] || die '--prefer-version requires a version.'
                prefer_version=1; fwd+=("$1" "$2"); shift 2 ;;
            --enable-reasoning-summaries) fwd+=("$1"); shift ;;
            --session-id)
                [[ $# -ge 2 ]] || die '--session-id requires a value.'
                session_id_present=1
                fwd+=("$1" "$2"); shift 2 ;;
            --session-id=*)
                session_id_present=1
                fwd+=("$1"); shift ;;
            --model)
                [[ $# -ge 2 ]] || die '--model requires a value.'
                model="$2"; fwd+=("$1" "$2"); shift 2 ;;
            -C|--change-dir)
                [[ $# -ge 2 && -n "$2" ]] || { log_error "$1 requires a value (an existing directory)."; return 1; }
                change_dir="$2"; change_index=${#fwd[@]}
                change_indices+=("$change_index")
                fwd+=("$1" "$2"); shift 2 ;;
            --change-dir=*)
                change_dir="${1#*=}"
                [[ -n "$change_dir" ]] || { log_error '--change-dir requires an existing directory.'; return 1; }
                change_index=${#fwd[@]}
                change_indices+=("$change_index")
                fwd+=(--change-dir "$change_dir"); shift ;;
            --reasoning-effort|--agent|--mode|--context|--add-dir|--log-level|--output-format)
                [[ $# -ge 2 ]] || die "$1 requires a value."
                fwd+=("$1" "$2"); shift 2 ;;
            --plan) fwd+=("$1"); shift ;;
            -h|--help) _launch_plan_usage; return 2 ;;
            -*) fwd+=("$1"); shift ;;
            *) if [[ -z "$prompt" ]]; then prompt="$1"; else fwd+=("$1"); fi; shift ;;
        esac
    done

    # Resolve relative paths once, while the caller remains in its original cwd.
    COPILOT_CWD="$(cd -- "${change_dir:-.}" 2>/dev/null && pwd -P)" || {
        log_error "Change directory must be an existing filesystem directory: '$change_dir'."
        return 1
    }
    # shellcheck disable=SC2034  # consumed by launchers after planning
    COPILOT_EXE="$(cd -- "$COPILOT_CWD" && {
        local exe
        exe="$(resolve_copilot)" || return 1
        if [[ "$exe" == /* ]]; then printf '%s\n' "$exe"
        else readlink -f -- "$exe"; fi
    })" || return 1

    if [[ "$assisted_approval" == "1" && "$no_experimental" == "1" ]]; then
        log_warn '--assisted-approval may not work with --no-experimental.'
    fi

    # Passthrough commands (update/help) bypass the built args entirely.
    if [[ "$prompt" == "update" || "$prompt" == "help" ]]; then
        # shellcheck disable=SC2034
        COPILOT_PASSTHROUGH=1
        COPILOT_ARGS=("$prompt")
        [[ ${#fwd[@]} -gt 0 ]] && COPILOT_ARGS+=("${fwd[@]}")
        [[ ${#passthrough_args[@]} -gt 0 ]] && COPILOT_ARGS+=("${passthrough_args[@]}")
        return 0
    fi

    [[ "$fleet" == "0" || -n "$prompt" || -n "$interactive" ]] ||
        die '--fleet requires a prompt or --interactive.'
    [[ -z "$auto_tier" || -z "$model" || "$model" == auto ]] ||
        die '--auto-tier can only be combined with --model auto.'
    [[ "$no_mouse" == "0" || "$mouse_present" == "0" ]] ||
        die '--no-mouse cannot be combined with --mouse.'
    [[ -z "$prompt" || -z "$interactive" ]] || die 'Choose a prompt or --interactive, not both.'
    if [[ "$no_eager_powershell" == "1" ]]; then
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*) ;;
            *) die '--no-eager-powershell-resolution is only supported on Windows.' ;;
        esac
    fi
    if [[ "$prefer_version" == "1" && ! " ${fwd[*]} " == *" --no-auto-update "* ]]; then
        fwd+=(--no-auto-update)
    fi

    if [[ ${#mcp_github_auth[@]} -gt 0 ]]; then
        (cd -- "$COPILOT_CWD" &&
            _shm_validate_mcp_github_auth additional_mcp mcp_github_auth) || return $?
    fi
    if [[ "$change_index" -ge 0 ]]; then
        fwd[change_index+1]="$COPILOT_CWD"
        # Repeated directory flags resolve from the caller, never sequentially.
        local i
        for i in "${change_indices[@]}"; do
            if [[ "$i" -ne "$change_index" ]]; then
                unset 'fwd[i]' 'fwd[i+1]'
            fi
        done
        fwd=("${fwd[@]}")
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
        chosen="$(cd -- "$COPILOT_CWD" &&
            _shm_resolve_resume "$resume_latest" "$show_picker" "$include_unnamed" "$selector")" || return $?
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
    _shm_gate_remote
    return 0
}

# Check the actual native directory, not cached session repository metadata.
# Resuming does not change the launch directory; native -C overrides do.
_shm_gate_remote() {
    local requested=0 disabled=0 value option='' directory="$COPILOT_CWD"
    local filtered=() urls identity
    for value in "${COPILOT_ARGS[@]}"; do
        if [[ -n "$option" ]]; then
            case "$option" in -C|--change-dir) directory="$value" ;; esac
            filtered+=("$value"); option=''; continue
        fi
        case "$value" in
            --remote) requested=1 ;;
            --no-remote) disabled=1 ;;
            --no-remote-export) disabled=1; filtered+=("$value") ;;
            --change-dir=*) directory="${value#*=}"; filtered+=("$value") ;;
            --deny-tool|--allow-tool|--deny-url|--allow-url|--add-dir|--model|--reasoning-effort|--agent|--mode|--context|--log-level|--output-format|--session-id|--name|--resume|--resume-session|--usage-output-file|--enable-mcp-server|--disable-mcp-server|--additional-mcp-config|--mcp-github-auth|--interactive|-i|--prompt|-p|--auto-tier|--dynamic-retrieval|--mouse|--prefer-version|-C|--change-dir)
                option="$value"; filtered+=("$value") ;;
            *) filtered+=("$value") ;;
        esac
    done
    if [[ "$disabled" == 1 ]]; then
        filtered+=(--no-remote)
    elif [[ "$requested" == 1 ]]; then
        if have_cmd git &&
           [[ "$(git -C "$directory" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]] &&
           urls="$(git -C "$directory" config --get-all remote.origin.url 2>/dev/null)" &&
           [[ -n "$urls" && "$urls" != *$'\n'* ]] &&
           [[ "${urls,,}" == https://github.com/* || "${urls,,}" == git@github.com:* ||
              "${urls,,}" == ssh://git@github.com/* ]] &&
           identity="$(copilot_origin_identity "$urls")" && [[ -n "$identity" ]]; then
            filtered+=(--remote)
        else
            log_warn 'Remote control not enabled: the effective launch directory needs a Git worktree with one recognized upstream GitHub origin. Continuing locally.'
            filtered+=(--no-remote)
        fi
    fi
    COPILOT_ARGS=("${filtered[@]}")
}

_shm_validate_mcp_github_auth() {
    local -n _configs="$1" _scopes="$2"
    require_cmd node
    local helper value
    helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mcp-auth.js"
    {
        for value in "${_configs[@]}"; do printf 'config\0%s\0' "$value"; done
        for value in "${_scopes[@]}"; do printf 'auth\0%s\0' "$value"; done
    } | COPILOT_AUTH_HOME="$(copilot_home)" node "$helper"
}

# Preview diagnostics are not the reusable plan: redact inline MCP configuration.
copilot_preview_args() {
    local value redact_next=0
    for value in "${COPILOT_ARGS[@]}"; do
        if [[ "$redact_next" == "1" ]]; then
            [[ "$value" == @* ]] || value='<inline MCP config redacted>'
            redact_next=0
        elif [[ "$value" == --additional-mcp-config ]]; then
            redact_next=1
        elif [[ "$value" == --additional-mcp-config=* && "$value" != --additional-mcp-config=@* ]]; then
            value='--additional-mcp-config=<inline MCP config redacted>'
        fi
        printf ' %q' "$value"
    done
}

# _shm_apply_mcp_autoconnect ENABLE_ARRAY DISABLE_ARRAY — append --disable-mcp-server
# flags per the autoConnect glob policy, then per explicit --disable-mcp-server.
_shm_apply_mcp_autoconnect() {
    local -n _enable="$1"; local -n _disable="$2"
    local cfg; cfg="$(copilot_home)/mcp-config.json"
    local cwd; cwd="${COPILOT_CWD:-$(pwd -P)}"
    [[ "$cfg" == /* ]] || cfg="$cwd/$cfg"

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
