# Legacy manual-source entry point; compinit discovers _shm_commands instead.
# --github-account and the other contracts live in lib/completion.sh.
_SHM_COMPLETION_LOAD_ONLY=1
source "${${(%):-%x}:A:h}/_shm_commands"
unset _SHM_COMPLETION_LOAD_ONLY
local _shm_command
for _shm_command in ${${(f)"$(_shm_completion_commands)"}}; do
    compdef _shm_git_command "$_shm_command"
done
zstyle ':completion:*:*:git-worktree-*:*' matcher-list 'l:|=* r:|=*'
unset _shm_command
