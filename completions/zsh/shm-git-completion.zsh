#compdef git-status-summary git-status-segment git-sync git-stale-branch git-worktree-list git-worktree-current git-worktree-root git-worktree-path git-worktree-new git-worktree-add git-worktree-remove git-worktree-switch git-worktree-prune git-worktree-repair git-worktree-lock git-worktree-unlock git-worktree-move git-worktree-update git-worktree-update-all git-branch-list git-tag-list git-branch-switch git-branch-remove git-stash-save git-stash-restore git-config-set git-restore
# Zsh completion for the Shmuelie Git commands.

_shm_completion_repository() {
    local repo='.' option
    local -i i
    for ((i=2; i<CURRENT; i++)); do
        option="${words[i]}"
        case "$option" in
            -C|--repository-path)
                (( i + 1 < CURRENT )) || return 1
                repo="${words[i+1]}"; ((i+=1)) ;;
            --path)
                case "${words[1]}" in
                    git-worktree-add|git-worktree-new|git-worktree-list|git-worktree-current|git-worktree-root|git-worktree-path|git-worktree-prune|git-worktree-update|git-worktree-update-all|git-sync|git-status-summary|git-stale-branch|git-branch-*|git-tag-list|git-stash-*|git-config-set|git-restore)
                        (( i + 1 < CURRENT )) || return 1
                        repo="${words[i+1]}"; ((i+=1)) ;;
                    git-worktree-switch|git-worktree-remove)
                        ((i+=1)) ;;
                esac ;;
            --worktree-path|--kind|-k|--user|-u|--reason|--expire|--jobs|--organization|--name|--exclude|--github-account|--scope|--source|--message|--stash)
                ((i+=1)) ;;
            --remote) [[ "${words[1]}" == git-branch-list ]] || ((i+=1)) ;;
        esac
    done
    [[ -n "$repo" && -d "$repo" ]] || return 1
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
    print -r -- "$repo"
}
_shm_worktree_branches() {
    local repo
    repo="$(_shm_completion_repository)" || return 0
    git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p'
}
_shm_local_branches() {
    local repo line
    repo="$(_shm_completion_repository)" || return 0
    while IFS= read -r line; do
        [[ "$line" == *'|' ]] && print -r -- "${line%|}"
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)|%(worktreepath)' refs/heads/ 2>/dev/null)
    return 0
}
_shm_existing_branch() {
    local -a branches
    branches=(${(f)"$(_shm_worktree_branches)"})
    _describe 'worktree branch' branches
}
_shm_local_branch() {
    local -a branches
    branches=(${(f)"$(_shm_local_branches)"})
    _describe 'local branch' branches
}

_shm_git_command() {
    local command="$words[1]"
    local -a common_repo auth mutation
    common_repo=('--path[repository or child path]:repository:_directories' '-C[repository or child path]:repository:_directories')
    auth=('--github-account[map host/owner to account]:mapping:' '--no-github-account-resolve[disable account resolution]')
    mutation=('--confirm[ask before mutation]' '--dry-run[preview]' '--whatif[preview]')
    case "$command" in
        git-worktree-add)
            _arguments "${common_repo[@]}" '--worktree-path[destination]:destination:_directories' '--dry-run[preview]' '--whatif[preview]' '1:branch:_shm_local_branch' ;;
        git-worktree-new)
            _arguments "${common_repo[@]}" '--worktree-path[destination]:destination:_directories' '--kind[branch kind]:kind:(user feature release)' '--user[user segment]:user:' '--no-prefix[use name verbatim]' '--dry-run[preview]' '--whatif[preview]' '1:work name:' ;;
        git-worktree-switch)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[actual worktree path]:worktree:_directories' '1:branch:_shm_existing_branch' ;;
        git-worktree-remove)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[actual worktree path]:worktree:_directories' '--keep-branch[retain backing branch]' '--delete-branch[legacy cleanup flag]' '--delete-branch=[legacy cleanup setting]:boolean:(true false)' '--force[force operation]' "${mutation[@]}" '1:branch:_shm_existing_branch' ;;
        git-worktree-lock)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[address positional target as a path]' '--reason[lock reason]:reason:' '--dry-run[preview]' '--whatif[preview]' '1:branch or path:_shm_existing_branch' ;;
        git-worktree-unlock)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[address positional target as a path]' '--dry-run[preview]' '--whatif[preview]' '1:branch or path:_shm_existing_branch' ;;
        git-worktree-move)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[address positional target as a path]' '--force[force operation]' '--dry-run[preview]' '--whatif[preview]' '1:branch or path:_shm_existing_branch' '2:destination:_directories' ;;
        git-worktree-prune)
            _arguments "${common_repo[@]}" '--expire[expiration]:expiration:' '--dry-run[preview]' '--whatif[preview]' ;;
        git-worktree-repair)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--dry-run[preview]' '--whatif[preview]' '*:worktree path:_directories' ;;
        git-worktree-update)
            _arguments "${common_repo[@]}" '--check-remote[query remote refs]' "${auth[@]}" '--changed-only[actionable rows only]' '--json[JSON output]' '--dry-run[preview]' '--whatif[preview]' ;;
        git-worktree-update-all)
            _arguments "${common_repo[@]}" '--organization[organization glob]:glob:' '--name[repository glob]:glob:' '--exclude[exclude glob]:glob:' '--jobs[parallel jobs]:jobs:' '--check-remote[query remote refs]' "${auth[@]}" '--changed-only[actionable rows only]' '--table[table overview]' '--json[JSON output]' '--dry-run[preview]' '--whatif[preview]' ;;
        git-sync)
            _arguments "${common_repo[@]}" '--no-prune[do not prune]' "${auth[@]}" '--json[JSON output]' '--dry-run[preview]' '--whatif[preview]' '1:remote:' ;;
        git-status-segment)
            _arguments '--no-change-counts[omit file change counts]' '--no-color[omit ANSI color]' '--ps1[mark ANSI as non-printing]' '1:repository path:_directories' ;;
        git-branch-list)
            _arguments "${common_repo[@]}" '--local[local branches]' '--remote[remote branches]' '--json[JSON output]' ;;
        git-tag-list)
            _arguments "${common_repo[@]}" '--name[tag glob]:pattern:' '--json[JSON output]' '*:pattern:' ;;
        git-branch-switch)
            _arguments "${common_repo[@]}" "${mutation[@]}" '--create[create new branch]' '--create-new[create new branch]' '--track[track remote branch]' '--discard-changes[discard local changes]' '--force[discard local changes]' '1:branch:' ;;
        git-branch-remove)
            _arguments "${common_repo[@]}" "${mutation[@]}" '--remote[configured remote]:remote:' '--force[allow unmerged local deletion]' '1:branch:' ;;
        git-stash-save)
            _arguments "${common_repo[@]}" "${mutation[@]}" '--keep-index[retain index]' '--include-untracked[save untracked files]' '--include-ignored[save ignored files too]' '--all[save ignored files too]' '--message[stash message]:message:' '--json[JSON output]' '--verbose[verbose output]' ;;
        git-stash-restore)
            _arguments "${common_repo[@]}" "${mutation[@]}" '--stash[stash selector]:stash:' ;;
        git-config-set)
            _arguments "${common_repo[@]}" "${mutation[@]}" '--scope[config scope]:scope:(local global system)' '1:key:' '2:value:' ;;
        git-restore)
            _arguments "${common_repo[@]}" "${mutation[@]}" '--include-index[restore index too]' '--source[source tree-ish]:revision:' '*:file:_files' ;;
        *)
            _arguments "${common_repo[@]}" '--json[JSON output]' '--string[formatted status only]' '--remote[remote]:remote:' '--user[user]:user:' '--all[all branches]' '--include-never-pushed[include local-only branches]' '--include-pr-status[query PR status]' '1:branch:' ;;
    esac
}

zstyle ':completion:*:*:git-worktree-*:*' matcher-list 'l:|=* r:|=*'
compdef _shm_git_command \
    git-status-summary git-status-segment git-sync git-stale-branch \
    git-worktree-list git-worktree-current git-worktree-root git-worktree-path \
    git-worktree-new git-worktree-add git-worktree-remove git-worktree-switch \
    git-worktree-prune git-worktree-repair git-worktree-lock git-worktree-unlock \
    git-worktree-move git-worktree-update git-worktree-update-all \
    git-branch-list git-tag-list git-branch-switch git-branch-remove \
    git-stash-save git-stash-restore git-config-set git-restore
