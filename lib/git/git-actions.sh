#!/usr/bin/env bash
# Mutation command implementations ported from Shmuelie.Git.
# shellcheck disable=SC2034 # Shared flags are consumed by sourced command helpers.

git_branch_switch() {
    local repo_arg='.' repo branch='' create=0 track=0 force=0 GIT_CONFIRM=0 args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-branch-switch [options] <branch>
  --path, -C <directory>       Target repository.
  --create                    Create at HEAD (cannot combine with --track).
  --track                     Create from an explicit remote branch, e.g. origin/topic.
  --discard-changes, --force   Discard local changes; never bypass worktree protection.
  --confirm                   Ask before switching (EOF/anything except y/yes declines).
  --dry-run, --whatif          Preview without changing anything.
Existing local branches are required by default; remote guessing is disabled.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --create|--create-new) create=1; shift ;;
            --track) track=1; shift ;;
            --discard-changes|--force) force=1; shift ;;
            --confirm) GIT_CONFIRM=1; shift ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            --) shift; [[ $# == 1 && -z "$branch" ]] || die 'Specify one branch.'; branch="$1"; shift ;;
            -*) die "Unknown option: $1" ;;
            *) [[ -z "$branch" ]] || die 'Specify one branch.'; branch="$1"; shift ;;
        esac
    done
    [[ "$create$track" != 11 ]] || die '--create and --track cannot be combined.'
    require_cmd git
    repo="$(git_resolve_repository_path "$repo_arg")" || return
    git_literal_branch "$repo" "$branch"
    args=(switch --no-guess)
    if [[ "$track" == 1 ]]; then
        git -C "$repo" show-ref --verify -- "refs/remotes/$branch" >/dev/null || return
        args+=(--track)
    elif [[ "$create" == 1 ]]; then
        args+=(--no-track --create "$branch")
    fi
    [[ "$force" == 1 ]] && args+=(--discard-changes)
    args+=(--)
    [[ "$create" == 1 ]] || args+=("$branch")
    local action="Switch to branch '$branch' in '$repo'"
    [[ "$create" == 1 ]] && action="Create and $action"
    [[ "$track" == 1 ]] && action="Track remote and $action"
    [[ "$force" == 1 ]] && action+=', discarding local changes'
    git_should_process "$action" || return 0
    git -C "$repo" "${args[@]}"
}

git_branch_remove() {
    local repo_arg='.' repo branch='' remote='' force=0 GIT_CONFIRM=0 args remotes found=0 candidate
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-branch-remove [options] <branch>
  --path, -C <directory>   Target repository (bare supported).
  --force                 Permit unmerged LOCAL branch deletion.
  --remote <name>         Delete on this configured remote, not locally.
  --confirm               Ask before deletion; never auto-accept EOF.
  --dry-run, --whatif      Preview without deletion or push.
Local deletion uses git branch -d by default. --remote and --force are exclusive.
Only literal branch names or refs/heads/<name> are accepted.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --remote) git_option_value "$@"; remote="$2"; shift 2 ;;
            --force) force=1; shift ;;
            --confirm) GIT_CONFIRM=1; shift ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            --) shift; [[ $# == 1 && -z "$branch" ]] || die 'Specify one branch.'; branch="$1"; shift ;;
            -*) die "Unknown option: $1" ;;
            *) [[ -z "$branch" ]] || die 'Specify one branch.'; branch="$1"; shift ;;
        esac
    done
    [[ -z "$remote" || "$force" == 0 ]] || die '--remote and --force cannot be combined.'
    require_cmd git
    repo="$(git_resolve_repository_path "$repo_arg" 1)" || return
    branch="${branch#refs/heads/}"
    git_literal_branch "$repo" "$branch"
    local action="Delete merged local branch '$branch' in '$repo'"
    if [[ -n "$remote" ]]; then
        [[ "$remote" != -* ]] || die "Invalid remote: '$remote'."
        remotes="$(git -C "$repo" remote)" || return
        while IFS= read -r candidate; do
            [[ "$remote" != "$candidate" ]] || found=1
        done <<< "$remotes"
        [[ "$found" == 1 ]] || die "Configured remote '$remote' was not found."
        args=(-c "remote.$remote.mirror=false" push --delete --no-follow-tags \
            --recurse-submodules=no -- "$remote" "refs/heads/$branch")
        action="Delete branch '$branch' on remote '$remote' in '$repo'"
    elif [[ "$force" == 1 ]]; then
        args=(branch -D -- "$branch")
        action="Delete local branch '$branch' in '$repo', allowing unmerged commits"
    else
        args=(branch -d -- "$branch")
    fi
    git_should_process "$action" || return 0
    git -C "$repo" "${args[@]}"
}

git_config_set() {
    local repo_arg='.' repo scope=local GIT_CONFIRM=0 operands=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-config-set [options] [--] <key> <value>
  --path, -C <directory>          Git working directory.
  --scope <local|global|system>   Configuration scope (default: local).
  --confirm                      Ask before writing.
  --dry-run, --whatif             Preview without writing.
Values are literal, including empty strings and leading dashes. Put options
before the key. Global/system scope also works outside repositories.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --scope) git_option_value "$@"; scope="$2"; shift 2 ;;
            --confirm) GIT_CONFIRM=1; shift ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            --) shift; operands=("$@"); break ;;
            -*) die "Unknown option: $1" ;;
            *) operands=("$@"); break ;;
        esac
    done
    [[ ${#operands[@]} == 2 && -n "${operands[0]}" ]] || die 'Specify a nonempty key and a value.'
    case "$scope" in local|global|system) ;; *) die "Invalid configuration scope: '$scope'." ;; esac
    require_cmd git
    if [[ "$scope" == local ]]; then
        repo="$(git_resolve_repository_path "$repo_arg" 1)" || return
    else
        [[ -d "$repo_arg" ]] || die "Directory not found: '$repo_arg'."
        repo="$(cd "$repo_arg" && pwd -P)" || return
    fi
    git_should_process "Set $scope Git configuration '${operands[0]}' in '$repo'" || return 0
    git -C "$repo" config "--$scope" -- "${operands[@]}"
}

git_stash_save() {
    local repo_arg='.' repo keep=0 untracked=0 ignored=0 message='' GIT_CONFIRM=0
    local before after push_output args scope='tracked' result
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-stash-save [options]
  --path, -C <directory>   Target working tree.
  --keep-index            Keep staged changes in the index and working tree.
  --include-untracked     Save untracked files too (not ignored files).
  --include-ignored, --all Save untracked and ignored files too.
  --message <text>        Literal message; blank/whitespace uses Git's default.
  --json                  Emit the created stash identity, or null for no new stash.
  --confirm               Ask before saving.
  --dry-run, --whatif      Preview without mutation.
Avoid concurrent stash writers; before/push/after reads are not an atomic transaction.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --keep-index) keep=1; shift ;;
            --include-untracked) untracked=1; shift ;;
            --include-ignored|--all) ignored=1; shift ;;
            --message) [[ $# -ge 2 ]] || die '--message requires a value.'; message="$2"; shift 2 ;;
            --json) JSON=1; shift ;;
            --confirm) GIT_CONFIRM=1; shift ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
    [[ "$untracked$ignored" != 11 ]] || die 'Use either --include-untracked or --include-ignored, not both.'
    require_cmd git; require_cmd jq
    repo="$(git_resolve_repository_path "$repo_arg")" || return
    before="$(git -C "$repo" for-each-ref --format='%(objectname)' -- refs/stash)" || return
    args=(stash push)
    [[ "$keep" == 1 ]] && args+=(--keep-index)
    if [[ "$untracked" == 1 ]]; then args+=(--include-untracked); scope='tracked and untracked'; fi
    if [[ "$ignored" == 1 ]]; then args+=(--all); scope='tracked, untracked and ignored'; fi
    [[ ! "$message" =~ [^[:space:]] ]] || args+=(-m "$message")
    if ! git_should_process "Save $scope changes in a stash in '$repo' (keep index: $keep)"; then
        [[ "$JSON" != 1 ]] || printf 'null\n'
        return 0
    fi
    local code
    if push_output="$(git -C "$repo" "${args[@]}")"; then
        :
    else
        code=$?
        [[ -z "$push_output" ]] || printf '%s\n' "$push_output" >&2
        log_error "git stash push failed in '$repo'; no stash creation was reported."
        return "$code"
    fi
    log_verbose "$push_output"
    after="$(git_ref_records "$repo" '%(objectname)%00%(contents:subject)' 2 refs/stash)" || return
    if [[ "$(jq -r '.[0][0] // ""' <<< "$after")" == "$before" ]]; then
        [[ "$JSON" != 1 ]] || printf 'null\n'
        [[ "$JSON" == 1 ]] || printf 'No new stash created.\n'
        return 0
    fi
    result="$(jq --arg repo "$repo" '.[0] |
        {objectId:.[0], subject:.[1], repositoryPath:$repo}' <<< "$after")" || return
    if [[ "$JSON" == 1 ]]; then printf '%s\n' "$result"
    else jq -r '"Saved stash \(.objectId): \(.subject)"' <<< "$result"; fi
}

git_stash_restore() {
    local repo_arg='.' repo stash='stash@{0}' GIT_CONFIRM=0 index
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-stash-restore [--path|-C <directory>] [--stash 'stash@{n}']
                         [--confirm] [--dry-run|--whatif]
Pop the newest stash by default. Native git stash pop keeps entries on failure
or conflict (which may leave partially restored files). No apply/drop retry.
Selectors must be canonical nonnegative 32-bit stash@{n} positions, not object IDs.
Avoid concurrent stash writers while confirming or restoring.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --stash) git_option_value "$@"; stash="$2"; shift 2 ;;
            --confirm) GIT_CONFIRM=1; shift ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
    [[ "$stash" =~ ^stash@\{(0|[1-9][0-9]*)\}$ ]] ||
        die 'Expected an exact stash@{n} selector.'
    index="${BASH_REMATCH[1]}"
    [[ ${#index} -le 10 && "$index" -le 2147483647 ]] ||
        die 'Stash index exceeds the nonnegative 32-bit range.'
    require_cmd git
    repo="$(git_resolve_repository_path "$repo_arg")" || return
    git_should_process "Pop '$stash' in '$repo' (remove only on success)" || return 0
    git -C "$repo" stash pop -- "$stash"
}

git_restore_items() {
    local repo_arg='.' repo include_index=0 source='' GIT_CONFIRM=0 files=() args tree unmerged
    local GIT_NO_LAZY_FETCH=1
    export GIT_NO_LAZY_FETCH
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: git-restore [options] -- <literal-file-or-directory>...
  --path, -C <directory>   Target working tree; files are relative to this directory.
  --include-index         Restore both index and working tree (default source: HEAD).
  --source <revision>     Explicit local tree-ish instead of the default source.
  --confirm               Ask before discarding changes.
  --dry-run, --whatif      Validate and preview without restoring.
Default: restore only the working tree from the index, preserving staged changes.
Quote wildcard-like names: they are literal Git paths, not pathspec patterns.
Unmerged entries are refused. Git may partially restore files on native failure.
EOF
                return ;;
            --path|-C) git_option_value "$@"; repo_arg="$2"; shift 2 ;;
            --source) git_option_value "$@"; source="$2"; shift 2 ;;
            --include-index) include_index=1; shift ;;
            --confirm) GIT_CONFIRM=1; shift ;;
            --dry-run|--whatif) DRY_RUN=1; shift ;;
            --) shift; files+=("$@"); break ;;
            -*) die "Unknown option: $1 (use -- before file operands)." ;;
            *) files+=("$1"); shift ;;
        esac
    done
    [[ ${#files[@]} -gt 0 ]] || die 'Specify at least one literal file or directory.'
    local file
    for file in "${files[@]}"; do
        [[ -n "$file" && ! "$file" =~ [[:cntrl:]] ]] || die 'File paths must be nonempty and contain no control characters.'
    done
    [[ "$source" != -* && ! "$source" =~ [[:cntrl:]] ]] || die 'Invalid source revision.'
    require_cmd git
    repo="$(git_resolve_repository_path "$repo_arg")" || return
    unmerged="$(git -C "$repo" --literal-pathspecs ls-files --unmerged -- "${files[@]}")" || return
    [[ -z "$unmerged" ]] || die 'Selected paths have unmerged index entries; resolve conflicts explicitly.'
    args=(--literal-pathspecs restore --worktree --no-recurse-submodules)
    local source_description='the index' destination='working-tree paths'
    if [[ -n "$source" || "$include_index" == 1 ]]; then
        source="${source:-HEAD}"
        tree="$(git -C "$repo" rev-parse --verify --end-of-options "$source^{tree}")" || return
        args+=("--source=$tree")
        source_description="'$source' ($tree)"
    fi
    if [[ "$include_index" == 1 ]]; then
        args+=(--staged); destination='index and working-tree paths'
    fi
    git_should_process "Restore $destination from $source_description in '$repo': ${files[*]}" || return 0
    git -C "$repo" "${args[@]}" -- "${files[@]}"
}
