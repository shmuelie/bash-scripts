#compdef git-worktree-switch git-worktree-remove git-worktree-add
# shm-git-completion.zsh — zsh completion for the git-worktree-* commands.
#
# Suggests worktree branch names for git-worktree-switch/remove and local
# branches for git-worktree-add, using substring matching.
#
# Enable by adding this directory to $fpath before `compinit`, e.g.:
#     fpath=(/path/to/completions/zsh $fpath); autoload -U compinit; compinit

_shm_worktree_branches() {
    git worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p'
}
_shm_local_branches() {
    git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
}

_git_worktree_switch() {
    local -a branches
    branches=(${(f)"$(_shm_worktree_branches)"})
    compadd -a branches
}
_git_worktree_remove() { _git_worktree_switch }
_git_worktree_add() {
    local -a branches
    branches=(${(f)"$(_shm_local_branches)"})
    compadd -a branches
}

# Enable substring matching for these completions.
zstyle ':completion:*' matcher-list 'l:|=* r:|=*'

compdef _git_worktree_switch git-worktree-switch
compdef _git_worktree_remove git-worktree-remove
compdef _git_worktree_add git-worktree-add
