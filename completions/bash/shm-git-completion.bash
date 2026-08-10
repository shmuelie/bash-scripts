#!/usr/bin/env bash
# shm-git-completion.bash — bash completion for the git-worktree-* commands.
#
# Replaces the compiled WorktreePredictor: suggests worktree branch names for
# git-worktree-switch/remove (existing worktrees) and any local branch for
# git-worktree-add. Suggestions use substring (not just prefix) matching, so a
# middle fragment like "wim" surfaces "user/alex/wim-work".
#
# Enable:
#     source /path/to/completions/bash/shm-git-completion.bash

_shm_worktree_branches() {
    git worktree list --porcelain 2>/dev/null |
        sed -n 's#^branch refs/heads/##p'
}

_shm_local_branches() {
    git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
}

# _shm_complete_substring CANDIDATES... — fill COMPREPLY with candidates that
# contain the current word as a substring (case-insensitive).
_shm_complete_substring() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local shopt_was_set=0
    shopt -q nocasematch && shopt_was_set=1
    shopt -s nocasematch
    COMPREPLY=()
    local c
    for c in "$@"; do
        if [[ -z "$cur" || "$c" == *"$cur"* ]]; then
            COMPREPLY+=("$c")
        fi
    done
    [[ "$shopt_was_set" == 0 ]] && shopt -u nocasematch
    return 0
}

_shm_worktree_existing_complete() {
    local branches
    mapfile -t branches < <(_shm_worktree_branches)
    _shm_complete_substring "${branches[@]}"
}

_shm_worktree_add_complete() {
    local branches
    mapfile -t branches < <(_shm_local_branches)
    _shm_complete_substring "${branches[@]}"
}

complete -F _shm_worktree_existing_complete git-worktree-switch
complete -F _shm_worktree_existing_complete git-worktree-remove
complete -F _shm_worktree_add_complete git-worktree-add
