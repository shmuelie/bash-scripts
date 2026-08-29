#compdef git-status-summary git-status-segment git-sync git-stale-branch git-worktree-list git-worktree-current git-worktree-root git-worktree-path git-worktree-new git-worktree-add git-worktree-remove git-worktree-switch git-worktree-prune git-worktree-repair git-worktree-lock git-worktree-unlock git-worktree-move git-worktree-update git-worktree-update-all
# Zsh completion for the Shmuelie Git commands.

_shm_worktree_branches() {
    git worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p'
}
_shm_local_branches() {
    git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
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
    local -a common_repo auth
    common_repo=('--path[repository or child path]:repository:_directories' '-C[repository or child path]:repository:_directories')
    auth=('--github-account[map host/owner to account]:mapping:' '--no-github-account-resolve[disable account resolution]')
    case "$command" in
        git-worktree-add)
            _arguments "${common_repo[@]}" '--worktree-path[destination]:destination:_directories' '--dry-run[preview]' '--whatif[preview]' '1:branch:_shm_local_branch' ;;
        git-worktree-new)
            _arguments "${common_repo[@]}" '--worktree-path[destination]:destination:_directories' '--kind[branch kind]:kind:(user feature release)' '--user[user segment]:user:' '--no-prefix[use name verbatim]' '--dry-run[preview]' '--whatif[preview]' '1:work name:' ;;
        git-worktree-switch)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[actual worktree path]:worktree:_directories' '1:branch:_shm_existing_branch' ;;
        git-worktree-remove)
            _arguments '-C[repository]:repository:_directories' '--repository-path[repository]:repository:_directories' '--path[actual worktree path]:worktree:_directories' '--delete-branch[delete backing branch]' '--force[force operation]' '--dry-run[preview]' '--whatif[preview]' '1:branch:_shm_existing_branch' ;;
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
            _arguments "${common_repo[@]}" '--check-remote[query remote refs]' "${auth[@]}" '--json[JSON output]' '--dry-run[preview]' '--whatif[preview]' ;;
        git-worktree-update-all)
            _arguments "${common_repo[@]}" '--organization[organization glob]:glob:' '--name[repository glob]:glob:' '--exclude[exclude glob]:glob:' '--jobs[parallel jobs]:jobs:' '--check-remote[query remote refs]' "${auth[@]}" '--changed-only[actionable rows only]' '--json[JSON output]' '--dry-run[preview]' '--whatif[preview]' ;;
        git-sync)
            _arguments "${common_repo[@]}" '--no-prune[do not prune]' "${auth[@]}" '--json[JSON output]' '--dry-run[preview]' '--whatif[preview]' '1:remote:' ;;
        git-status-segment)
            _arguments '--no-change-counts[omit file change counts]' '--no-color[omit ANSI color]' '--ps1[mark ANSI as non-printing]' '1:repository path:_directories' ;;
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
    git-worktree-move git-worktree-update git-worktree-update-all
