#!/usr/bin/env bash
# git-common.sh — shared Git helpers ported from Shmuelie.Git.
#
# Provides repository resolution, worktree enumeration/targeting, GitHub
# account-aware fetch helpers, and branch/path derivation. Source common.sh first.

if [[ -n "${_SHM_GIT_COMMON_SOURCED:-}" ]]; then
    return 0
fi
_SHM_GIT_COMMON_SOURCED=1

SHM_FS="${SHM_FS:-$'\x1f'}"

# git_resolve_repository_path [PATH] [ALLOW_BARE] — validate PATH without
# changing the caller's working directory and print its absolute path.
git_resolve_repository_path() {
    local candidate="${1:-.}" allow_bare="${2:-0}" resolved inside bare
    if [[ ! -d "$candidate" ]]; then
        log_error "Git repository path not found: '$candidate'."
        return 1
    fi
    resolved="$(cd "$candidate" 2>/dev/null && pwd -P)" || {
        log_error "Git repository path not found: '$candidate'."
        return 1
    }
    inside="$(git -C "$resolved" rev-parse --is-inside-work-tree 2>/dev/null || true)"
    if [[ "$inside" == 'true' ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi
    if [[ "$allow_bare" == "1" ]]; then
        bare="$(git -C "$resolved" rev-parse --is-bare-repository 2>/dev/null || true)"
        if [[ "$bare" == 'true' ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi
    log_error "Not a git repository: path '$resolved' is not inside a git working tree."
    return 1
}

# git_worktrees [REPOSITORY] — emit structured SHM_FS-separated rows:
# PATH, COMMIT, BRANCH, BARE, DETACHED, LOCKED, LOCK_REASON, PRUNABLE,
# PRUNABLE_REASON. Empty reason fields are retained safely.
git_worktrees() {
    local repo="${1:-.}" path='' commit='' branch='' bare=0 detached=0
    local locked=0 lock_reason='' prunable=0 prunable_reason='' line raw

    _git_worktree_emit() {
        [[ -n "$path" ]] || return 0
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
            "$path" "$SHM_FS" "$commit" "$SHM_FS" "$branch" "$SHM_FS" \
            "$bare" "$SHM_FS" "$detached" "$SHM_FS" "$locked" "$SHM_FS" \
            "$lock_reason" "$SHM_FS" "$prunable" "$SHM_FS" "$prunable_reason"
    }

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            _git_worktree_emit
            path=''; commit=''; branch=''; bare=0; detached=0
            locked=0; lock_reason=''; prunable=0; prunable_reason=''
            continue
        fi
        case "$line" in
            'worktree '*)
                raw="${line#worktree }"
                if [[ -d "$raw" ]]; then
                    path="$(cd "$raw" 2>/dev/null && pwd -P || printf '%s' "$raw")"
                else
                    path="$raw"
                fi
                ;;
            'HEAD '*) commit="${line#HEAD }" ;;
            'branch refs/heads/'*) branch="${line#branch refs/heads/}" ;;
            'detached') branch='(detached)'; detached=1 ;;
            'bare') bare=1 ;;
            'locked') locked=1 ;;
            'locked '*) locked=1; lock_reason="${line#locked }" ;;
            'prunable') prunable=1 ;;
            'prunable '*) prunable=1; prunable_reason="${line#prunable }" ;;
        esac
    done < <(git -C "$repo" worktree list --porcelain)
    _git_worktree_emit
    unset -f _git_worktree_emit
}

git_worktree_branches() {
    local repo="${1:-.}" _path _commit branch _rest
    while IFS="$SHM_FS" read -r _path _commit branch _rest; do
        printf '%s\n' "$branch"
    done < <(git_worktrees "$repo")
}

git_path_contains() {
    local ref cand
    ref="$(_shm_fullpath "$1")"; ref="${ref%/}"
    cand="$(_shm_fullpath "$2")"
    [[ "$cand" == "$ref" || "$cand" == "$ref/"* ]]
}

_shm_fullpath() {
    local p="$1" dir base
    if [[ -d "$p" ]]; then
        (cd "$p" && pwd -P)
    else
        dir="$(dirname -- "$p")"
        base="$(basename -- "$p")"
        if [[ -d "$dir" ]]; then
            printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
        else
            case "$p" in
                /*) printf '%s\n' "$p" ;;
                *) printf '%s/%s\n' "$(pwd -P)" "$p" ;;
            esac
        fi
    fi
}

git_absolute_from_base() {
    local base="$1" path="$2"
    case "$path" in
        /*) _shm_fullpath "$path" ;;
        *) _shm_fullpath "$base/$path" ;;
    esac
}

# git_current_worktree [REPOSITORY] [CANDIDATE] — emit the row containing
# CANDIDATE. CANDIDATE defaults to REPOSITORY.
git_current_worktree() {
    local repo="${1:-.}" candidate="${2:-${1:-.}}" wt_path rest
    candidate="$(_shm_fullpath "$candidate")"
    while IFS="$SHM_FS" read -r wt_path rest; do
        if git_path_contains "$wt_path" "$candidate"; then
            printf '%s%s%s\n' "$wt_path" "$SHM_FS" "$rest"
            return 0
        fi
    done < <(git_worktrees "$repo")
    return 1
}

git_root_worktree() {
    local repo="${1:-.}" common_dir root_path wt_path rest is_bare
    common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
        log_error 'Not in a git repository.'
        return 1
    }
    is_bare="$(git -C "$repo" rev-parse --is-bare-repository 2>/dev/null || true)"
    if [[ "$is_bare" == 'true' ]]; then
        root_path="$(_shm_fullpath "$common_dir")"
    else
        root_path="$(_shm_fullpath "$(dirname -- "$common_dir")")"
    fi
    while IFS="$SHM_FS" read -r wt_path rest; do
        if [[ "$(_shm_fullpath "$wt_path")" == "$root_path" ]]; then
            printf '%s%s%s\n' "$wt_path" "$SHM_FS" "$rest"
            return 0
        fi
    done < <(git_worktrees "$repo")
    return 1
}

git_repo_name() {
    local repo="${1:-.}" url
    url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 1
    url="${url##*/}"
    printf '%s\n' "${url%.git}"
}

git_worktree_path() {
    local repo="${1:-.}" branch="$2" root_line root_path root_branch
    root_line="$(git_root_worktree "$repo")" || return 1
    IFS="$SHM_FS" read -r root_path _ root_branch _ <<< "$root_line"
    root_path="$(_shm_fullpath "$root_path")"
    root_path="${root_path%/}"

    local branch_path="${root_branch//\\//}"
    branch_path="${branch_path#/}"; branch_path="${branch_path%/}"
    local suffix="/$branch_path" container
    if [[ -n "$branch_path" && "$root_path" == *"$suffix" ]]; then
        container="${root_path%"$suffix"}"
    else
        container="$(dirname -- "$root_path")"
    fi
    printf '%s/%s\n' "$container" "$branch"
}

git_branch_user() {
    local repo="${1:-.}" candidate="${GITHUB_USER:-}" email
    if [[ -z "$candidate" ]]; then
        email="$(git -C "$repo" config --get user.email 2>/dev/null || true)"
        if [[ "$email" =~ ^([^@]+)@ ]]; then
            candidate="${BASH_REMATCH[1]}"
        fi
    fi
    [[ -n "$candidate" ]] || candidate="${USER:-}"
    candidate="$(printf '%s' "$candidate" | tr -c 'A-Za-z0-9._-' '-')"
    candidate="${candidate#-}"; candidate="${candidate%-}"
    [[ -n "$candidate" ]] ||
        die 'Could not determine a branch user name. Set GITHUB_USER or configure git user.email.'
    printf '%s\n' "$candidate"
}

git_operation() {
    local repo="${1:-.}" git_dir step='' total='' type=''
    git_dir="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null)" || return 0

    if [[ -d "$git_dir/rebase-merge" ]]; then
        [[ -f "$git_dir/rebase-merge/msgnum" ]] && step="$(tr -d '[:space:]' < "$git_dir/rebase-merge/msgnum")"
        [[ -f "$git_dir/rebase-merge/end" ]] && total="$(tr -d '[:space:]' < "$git_dir/rebase-merge/end")"
        if [[ -f "$git_dir/rebase-merge/interactive" ]]; then type='REBASE-i'; else type='REBASE-m'; fi
    elif [[ -d "$git_dir/rebase-apply" ]]; then
        [[ -f "$git_dir/rebase-apply/next" ]] && step="$(tr -d '[:space:]' < "$git_dir/rebase-apply/next")"
        [[ -f "$git_dir/rebase-apply/last" ]] && total="$(tr -d '[:space:]' < "$git_dir/rebase-apply/last")"
        if [[ -f "$git_dir/rebase-apply/rebasing" ]]; then type='REBASE'
        elif [[ -f "$git_dir/rebase-apply/applying" ]]; then type='AM'
        else type='AM/REBASE'; fi
    elif [[ -f "$git_dir/MERGE_HEAD" ]]; then type='MERGING'
    elif [[ -f "$git_dir/REVERT_HEAD" ]]; then type='REVERTING'
    elif [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then type='CHERRY-PICKING'
    elif [[ -f "$git_dir/BISECT_LOG" ]]; then type='BISECTING'
    fi
    if [[ -n "$type" ]]; then
        if [[ -n "$step" && -n "$total" ]]; then printf '%s %s/%s\n' "$type" "$step" "$total"
        else printf '%s\n' "$type"; fi
    fi
}

git_worktree_paths_equal() {
    [[ "$(_shm_fullpath "$1")" == "$(_shm_fullpath "$2")" ]]
}

# git_resolve_worktree_target REPOSITORY MODE VALUE — MODE is branch, path, or
# auto. Emits the complete worktree row.
git_resolve_worktree_target() {
    local repo="$1" mode="$2" value="$3" row wt_path _commit wt_branch
    local resolved_by_path=0 matches=()
    while IFS= read -r row; do
        IFS="$SHM_FS" read -r wt_path _commit wt_branch _ <<< "$row"
        case "$mode" in
            path)
                git_worktree_paths_equal "$wt_path" "$value" && matches+=("$row")
                ;;
            branch)
                [[ "$wt_branch" == "$value" ]] && matches+=("$row")
                ;;
            auto)
                if git_worktree_paths_equal "$wt_path" "$value"; then
                    matches=("$row")
                    resolved_by_path=1
                    break
                fi
                [[ "$wt_branch" == "$value" ]] && matches+=("$row")
                ;;
        esac
    done < <(git_worktrees "$repo")

    if [[ ${#matches[@]} -eq 0 ]]; then
        if [[ "$mode" == 'path' ]]; then
            log_error "No worktree was found at path '$value'."
        else
            log_error "No worktree was found for branch or path '$value'."
        fi
        return 1
    fi
    IFS="$SHM_FS" read -r _ _ wt_branch _ detached _ <<< "${matches[0]}"
    if [[ "$mode" != 'path' && "$resolved_by_path" == "0" &&
        "$wt_branch" == '(detached)' && ${#matches[@]} -gt 0 ]]; then
        log_error "Detached worktrees cannot be addressed by branch name. Use --path."
        return 1
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
        log_error "More than one worktree matched '$value'. Use --path."
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}

git_validate_github_host() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]
}

git_validate_github_account() {
    [[ "$1" =~ ^[A-Za-z0-9](-?[A-Za-z0-9])*$ ]]
}

git_validate_github_mapping() {
    local mapping="$1" key host owner account
    [[ "$mapping" == *=* ]] || return 1
    key="${mapping%%=*}"; account="${mapping#*=}"
    [[ "$key" == */* && "$key" != */*/* ]] || return 1
    host="${key%%/*}"; owner="${key#*/}"
    git_validate_github_host "$host" &&
        [[ "$owner" =~ ^[A-Za-z0-9_.-]+$ ]] &&
        git_validate_github_account "$account"
}

# git_github_remote_info URL — print HOST<SHM_FS>OWNER for URL, SSH, or SCP form.
git_github_remote_info() {
    local url="$1" host='' owner=''
    if [[ "$url" =~ ^[A-Za-z][A-Za-z0-9+.-]*://([^@/]+@)?([^/:]+)(:[0-9]+)?/([^/]+)/ ]]; then
        host="${BASH_REMATCH[2]}"; owner="${BASH_REMATCH[4]}"
    elif [[ "$url" =~ ^([^@]+@)?([^:/]+):([^/]+)/ ]]; then
        host="${BASH_REMATCH[2]}"; owner="${BASH_REMATCH[3]}"
    else
        return 1
    fi
    host="${host,,}"
    git_validate_github_host "$host" || return 1
    [[ "$owner" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    printf '%s%s%s\n' "$host" "$SHM_FS" "$owner"
}

# git_github_accounts — emit HOST<SHM_FS>ACCOUNT<SHM_FS>ACTIVE.
git_github_accounts() {
    have_cmd gh || return 0
    local line host='' account='' active=0
    while IFS= read -r line; do
        if [[ "$line" =~ Logged[[:space:]]in[[:space:]]to[[:space:]]([^[:space:]]+)[[:space:]]account[[:space:]]([^[:space:]]+) ]]; then
            if [[ -n "$host" ]]; then
                printf '%s%s%s%s%s\n' "$host" "$SHM_FS" "$account" "$SHM_FS" "$active"
            fi
            host="${BASH_REMATCH[1],,}"; account="${BASH_REMATCH[2]}"; active=0
            if ! git_validate_github_host "$host" || ! git_validate_github_account "$account"; then
                host=''; account=''
            fi
        elif [[ -n "$host" && "$line" =~ Active[[:space:]]account:[[:space:]]*(true|false) ]]; then
            [[ "${BASH_REMATCH[1]}" == 'true' ]] && active=1 || active=0
        fi
    done < <(gh auth status 2>&1 || true)
    if [[ -n "$host" ]]; then
        printf '%s%s%s%s%s\n' "$host" "$SHM_FS" "$account" "$SHM_FS" "$active"
    fi
}

git_is_auth_failure() {
    grep -Eqi 'Authentication failed|could not read Username|terminal prompts disabled|403 Forbidden|Repository not found|Permission (to .*)?denied|access denied|401 Unauthorized' <<< "$1"
}
