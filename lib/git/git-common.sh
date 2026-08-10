#!/usr/bin/env bash
# git-common.sh — shared Git helpers ported from Shmuelie.Git.
#
# Provides worktree enumeration, path resolution, repo-name and branch-user
# derivation used by the git-* commands. Source lib/common.sh first.

if [[ -n "${_SHM_GIT_COMMON_SOURCED:-}" ]]; then
    return 0
fi
_SHM_GIT_COMMON_SOURCED=1

# git_worktrees — emit one "PATH<TAB>COMMIT<TAB>BRANCH" line per worktree.
# Ported from Get-Worktrees. Branch is "(detached)" for detached HEADs and the
# git-reported path is kept even when the directory no longer resolves.
git_worktrees() {
    local path='' commit='' branch='' line
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            if [[ -n "$path" ]]; then
                printf '%s\t%s\t%s\n' "$path" "$commit" "$branch"
                path=''; commit=''; branch=''
            fi
            continue
        fi
        case "$line" in
            'worktree '*)
                local raw="${line#worktree }"
                if [[ -d "$raw" ]]; then
                    path="$(cd "$raw" 2>/dev/null && pwd -P || printf '%s' "$raw")"
                else
                    path="$raw"
                fi
                ;;
            'HEAD '*)   commit="${line#HEAD }" ;;
            'branch refs/heads/'*) branch="${line#branch refs/heads/}" ;;
            'detached') branch='(detached)' ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null)
    if [[ -n "$path" ]]; then
        printf '%s\t%s\t%s\n' "$path" "$commit" "$branch"
    fi
}

# git_worktree_branches — print the branch name of every worktree, one per line.
git_worktree_branches() {
    git_worktrees | cut -f3
}

# git_path_contains REFERENCE CANDIDATE — return 0 if CANDIDATE equals or is a
# child of REFERENCE. Ported from Test-PathContains (case-sensitive on Linux).
git_path_contains() {
    local ref cand
    ref="$(_shm_fullpath "$1")"; ref="${ref%/}"
    cand="$(_shm_fullpath "$2")"
    [[ "$cand" == "$ref" || "$cand" == "$ref/"* ]]
}

# _shm_fullpath PATH — normalize to an absolute path without requiring existence.
_shm_fullpath() {
    local p="$1"
    if [[ -d "$p" ]]; then
        (cd "$p" && pwd -P)
    else
        local dir base
        dir="$(dirname -- "$p")"
        base="$(basename -- "$p")"
        if [[ -d "$dir" ]]; then
            printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
        else
            # Fall back to lexical absolute path.
            case "$p" in
                /*) printf '%s\n' "$p" ;;
                *)  printf '%s/%s\n' "$(pwd -P)" "$p" ;;
            esac
        fi
    fi
}

# git_current_worktree — emit the worktree line containing the current directory.
git_current_worktree() {
    local cwd wt_path rest
    cwd="$(pwd -P)"
    while IFS=$'\t' read -r wt_path rest; do
        if git_path_contains "$wt_path" "$cwd"; then
            printf '%s\t%s\n' "$wt_path" "$rest"
        fi
    done < <(git_worktrees)
}

# git_root_worktree — emit the root (main) worktree line. Ported from
# Get-RootWorktree using the git common dir.
git_root_worktree() {
    local common_dir root_path wt_path rest
    common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [[ -z "$common_dir" ]]; then
        log_error 'Not in a git repository.'
        return 1
    fi
    root_path="$(_shm_fullpath "$(dirname -- "$common_dir")")"
    while IFS=$'\t' read -r wt_path rest; do
        if [[ "$(_shm_fullpath "$wt_path")" == "$root_path" ]]; then
            printf '%s\t%s\n' "$wt_path" "$rest"
            return 0
        fi
    done < <(git_worktrees)
    return 1
}

# git_repo_name — repository name from origin URL (sans .git). Ported from
# Get-RepositoryName.
git_repo_name() {
    local url
    url="$(git remote get-url origin 2>/dev/null)" || return 1
    url="${url##*/}"
    printf '%s\n' "${url%.git}"
}

# git_worktree_path BRANCH — compute the path a branch's worktree would use.
# Ported from Get-WorktreePath: the container is the root worktree's parent,
# accounting for the root's own branch subdirectory.
git_worktree_path() {
    local branch="$1" root_line root_path root_branch
    root_line="$(git_root_worktree)" || return 1
    root_path="$(_shm_fullpath "$(printf '%s' "$root_line" | cut -f1)")"
    root_path="${root_path%/}"
    root_branch="$(printf '%s' "$root_line" | cut -f3)"

    # Normalize the root branch to a path suffix (foo/bar -> /foo/bar).
    local branch_path="${root_branch//\\//}"
    branch_path="${branch_path#/}"; branch_path="${branch_path%/}"
    local suffix="/$branch_path"

    local container
    if [[ -n "$branch_path" && "$root_path" == *"$suffix" ]]; then
        container="${root_path%"$suffix"}"
    else
        container="$(dirname -- "$root_path")"
    fi
    printf '%s/%s\n' "$container" "$branch"
}

# git_branch_user — derive a branch user segment. Ported from Get-GitBranchUser:
# GITHUB_USER, then git user.email local part, then OS user; sanitized.
git_branch_user() {
    local candidate="${GITHUB_USER:-}"
    if [[ -z "$candidate" ]]; then
        local email
        email="$(git config --get user.email 2>/dev/null)"
        if [[ "$email" =~ ^([^@]+)@ ]]; then
            candidate="${BASH_REMATCH[1]}"
        fi
    fi
    if [[ -z "$candidate" ]]; then
        candidate="${USER:-}"
    fi
    candidate="$(printf '%s' "$candidate" | tr -c 'A-Za-z0-9._-' '-')"
    candidate="${candidate#-}"; candidate="${candidate%-}"
    if [[ -z "$candidate" ]]; then
        die 'Could not determine a branch user name. Set GITHUB_USER or configure git user.email.'
    fi
    printf '%s\n' "$candidate"
}
