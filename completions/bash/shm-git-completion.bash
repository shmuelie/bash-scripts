#!/usr/bin/env bash
# Bash completion for the Shmuelie Git commands.

_shm_worktree_branches() {
    local repo='.'
    for ((i=1; i<COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in
            -C|--repository-path) repo="${COMP_WORDS[i+1]}" ;;
        esac
    done
    git -C "$repo" worktree list --porcelain 2>/dev/null |
        sed -n 's#^branch refs/heads/##p'
}

_shm_local_branches() {
    local repo='.'
    for ((i=1; i<COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in
            --path|-C|--repository-path) repo="${COMP_WORDS[i+1]}" ;;
        esac
    done
    git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
}

_shm_complete_substring() {
    local cur="${COMP_WORDS[COMP_CWORD]}" shopt_was_set=0 c
    shopt -q nocasematch && shopt_was_set=1
    shopt -s nocasematch
    COMPREPLY=()
    for c in "$@"; do
        [[ -z "$cur" || "$c" == *"$cur"* ]] && COMPREPLY+=("$c")
    done
    [[ "$shopt_was_set" == 0 ]] && shopt -u nocasematch
}

_shm_git_complete() {
    local cmd="${COMP_WORDS[0]}" cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
    local options='' branches=()
    case "$prev" in
        --path|-C|--repository-path|--worktree-path)
            mapfile -t COMPREPLY < <(compgen -d -- "$cur"); return ;;
        --kind)
            mapfile -t COMPREPLY < <(compgen -W 'user feature release' -- "$cur"); return ;;
        --jobs)
            mapfile -t COMPREPLY < <(compgen -W '1 2 4 8 16' -- "$cur"); return ;;
    esac
    case "$cmd" in
        git-worktree-add)
            options='--path -C --worktree-path --dry-run --whatif --verbose --help'
            mapfile -t branches < <(_shm_local_branches) ;;
        git-worktree-new)
            options='--path -C --worktree-path --kind --user --no-prefix --dry-run --whatif --verbose --help' ;;
        git-worktree-switch)
            options='--path -C --repository-path --help'
            mapfile -t branches < <(_shm_worktree_branches) ;;
        git-worktree-remove)
            options='--path -C --repository-path --delete-branch --force --dry-run --whatif --verbose --help'
            mapfile -t branches < <(_shm_worktree_branches) ;;
        git-worktree-lock)
            options='--path -C --repository-path --reason --dry-run --whatif --verbose --help'
            mapfile -t branches < <(_shm_worktree_branches) ;;
        git-worktree-unlock)
            options='--path -C --repository-path --dry-run --whatif --verbose --help'
            mapfile -t branches < <(_shm_worktree_branches) ;;
        git-worktree-move)
            options='--path -C --repository-path --force --dry-run --whatif --verbose --help'
            mapfile -t branches < <(_shm_worktree_branches) ;;
        git-worktree-list)
            options='--path -C --json --help' ;;
        git-worktree-current|git-worktree-root|git-worktree-path)
            options='--path -C --help' ;;
        git-worktree-prune)
            options='--path -C --expire --dry-run --whatif --verbose --help' ;;
        git-worktree-repair)
            options='-C --repository-path --dry-run --whatif --verbose --help' ;;
        git-worktree-update)
            options='--path -C --check-remote --github-account --no-github-account-resolve --json --dry-run --whatif --verbose --help' ;;
        git-sync)
            options='--path -C --no-prune --github-account --no-github-account-resolve --json --dry-run --whatif --verbose --help' ;;
        git-worktree-update-all)
            options='--path -C --organization --name --exclude --jobs --check-remote --github-account --no-github-account-resolve --changed-only --json --dry-run --whatif --verbose --help' ;;
        git-status-summary)
            options='--path -C --json --string --help' ;;
        git-status-segment)
            options='--no-change-counts --no-color --ps1 --help' ;;
        git-stale-branch)
            options='--path -C --remote --user --all --include-never-pushed --include-pr-status --json --help' ;;
    esac
    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$options" -- "$cur")
    elif [[ ${#branches[@]} -gt 0 ]]; then
        _shm_complete_substring "${branches[@]}"
    fi
}

complete -F _shm_git_complete \
    git-status-summary git-status-segment git-sync git-stale-branch \
    git-worktree-list git-worktree-current git-worktree-root git-worktree-path \
    git-worktree-new git-worktree-add git-worktree-remove git-worktree-switch \
    git-worktree-prune git-worktree-repair git-worktree-lock git-worktree-unlock \
    git-worktree-move git-worktree-update git-worktree-update-all
