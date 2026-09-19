#!/usr/bin/env bash
# Shared command helpers for the Shmuelie.Git ports. Source common/git-common first.

git_option_value() {
    [[ $# -ge 2 && -n "$2" ]] || die "Option '$1' requires a nonempty value."
}

# Unlike common.sh's legacy confirm, explicit confirmation never auto-accepts EOF.
git_should_process() {
    should_process "$@" || return 1
    if [[ "${GIT_CONFIRM:-0}" == 1 ]]; then
        local reply=''
        printf '%s [y/N] ' "$*" >&2
        if ! IFS= read -r reply || [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            printf 'Declined: %s\n' "$*" >&2
            return 1
        fi
    fi
    return 0
}

git_literal_branch() {
    local repo="$1" branch="$2"
    [[ -n "$branch" && "$branch" != -* && "$branch" != refs/* &&
        "$branch" != HEAD && "$branch" != @ ]] ||
        die "Expected a literal branch name, not an option or revision: '$branch'."
    git -C "$repo" check-ref-format "refs/heads/$branch" ||
        die "Invalid branch name: '$branch'."
}
