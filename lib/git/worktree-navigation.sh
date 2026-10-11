#!/usr/bin/env bash
# Source with the repository root as $1 from an interactive Bash/zsh shell.
case "$-" in *i*) ;; *) return 0 ;; esac
if [[ $# != 1 || ! -d "$1/bin" || ! -d "$1/lib" ]]; then
    printf 'Error: Source worktree-navigation.sh with the bash-scripts repository root.\n' >&2
    return 1
fi
_SHM_WORKTREE_NAVIGATION_ROOT="$(cd -- "$1" && pwd -P)" || return 1

_shm_worktree_navigate() {
    local executable="$1" navigate=1 destination exit_code
    shift
    local -a args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stay-in-directory)
                navigate=0; args+=("$1"); shift ;;
            -h|--help)
                navigate=0; args+=("$1"); shift ;;
            --path|-C|--worktree-path|-k|--kind|-u|--user)
                args+=("$1"); shift
                if [[ $# -gt 0 ]]; then args+=("$1"); shift; fi ;;
            --)
                args+=("$@"); break ;;
            *)
                args+=("$1"); shift ;;
        esac
    done
    if [[ "$navigate" == 0 ]]; then
        "$_SHM_WORKTREE_NAVIGATION_ROOT/bin/$executable" "${args[@]}"
        return $?
    fi
    if destination="$("$_SHM_WORKTREE_NAVIGATION_ROOT/bin/$executable" "${args[@]}")"; then
        [[ -n "$destination" ]] || return 0
    else
        exit_code=$?
        [[ -z "$destination" ]] || printf '%s\n' "$destination" >&2
        return "$exit_code"
    fi
    if [[ "$destination" != /* || "$destination" == *$'\n'* || ! -d "$destination" ]]; then
        printf 'Error: %s did not return one existing absolute worktree directory.\n' "$executable" >&2
        return 1
    fi
    cd -- "$destination" || return $?
    printf '%s\n' "$destination"
}

git-worktree-new() { _shm_worktree_navigate git-worktree-new "$@"; }
git-worktree-add() { _shm_worktree_navigate git-worktree-add "$@"; }
