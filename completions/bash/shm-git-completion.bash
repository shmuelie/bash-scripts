#!/usr/bin/env bash
# Bash completion for every public command (legacy entry point retained).
# Contracts, including git-status-segment and git-worktree-prune/repair/lock/
# unlock/move/update-all, live in lib/completion.sh.
_SHM_COMPLETION_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=lib/completion.sh
source "$_SHM_COMPLETION_ROOT/lib/completion.sh"

_shm_bash_prepare() {
    _shm_bash_strip_prefix=''
    if ((COMP_CWORD > 2)) && [[ "${COMP_WORDS[COMP_CWORD-1]}" == @ && "${COMP_WORDS[COMP_CWORD-2]}" == --additional-mcp-config ]]; then
        _shm_completion_prepare "${COMP_WORDS[0]}" "@${COMP_WORDS[COMP_CWORD]}" \
            "${COMP_WORDS[@]:1:COMP_CWORD-2}"
        _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
        return
    elif ((COMP_CWORD > 3)) && [[ "${COMP_WORDS[COMP_CWORD-1]}" == @ && "${COMP_WORDS[COMP_CWORD-2]}" == = && "${COMP_WORDS[COMP_CWORD-3]}" == --additional-mcp-config ]]; then
        _shm_completion_prepare "${COMP_WORDS[0]}" "--additional-mcp-config=@${COMP_WORDS[COMP_CWORD]}" \
            "${COMP_WORDS[@]:1:COMP_CWORD-4}"
        _shm_bash_strip_prefix='--additional-mcp-config='
        _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
        return
    fi
    if ((COMP_CWORD > 2)) && [[ "${COMP_WORDS[COMP_CWORD-1]}" == = ]]; then
        local option="${COMP_WORDS[COMP_CWORD-2]}"
        if [[ "$option" == --* ]]; then
            _shm_completion_prepare "${COMP_WORDS[0]}" "$option=${COMP_WORDS[COMP_CWORD]}" \
                "${COMP_WORDS[@]:1:COMP_CWORD-3}"
            _shm_bash_strip_prefix="$option="
            _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
            return
        elif [[ "$option" == skills && "${COMP_WORDS[COMP_CWORD-3]}" == --dynamic-retrieval ]]; then
            _shm_completion_prepare "${COMP_WORDS[0]}" "skills=${COMP_WORDS[COMP_CWORD]}" \
                "${COMP_WORDS[@]:1:COMP_CWORD-3}"
            _shm_bash_strip_prefix='skills='
            _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
            return
        elif ((COMP_CWORD > 4)) && [[ "$option" == skills && "${COMP_WORDS[COMP_CWORD-3]}" == = && "${COMP_WORDS[COMP_CWORD-4]}" == --dynamic-retrieval ]]; then
            _shm_completion_prepare "${COMP_WORDS[0]}" "--dynamic-retrieval=skills=${COMP_WORDS[COMP_CWORD]}" \
                "${COMP_WORDS[@]:1:COMP_CWORD-5}"
            _shm_bash_strip_prefix='--dynamic-retrieval=skills='
            _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
            return
        fi
    elif ((COMP_CWORD > 1)) && [[ "${COMP_WORDS[COMP_CWORD]}" == = && "${COMP_WORDS[COMP_CWORD-1]}" == --* ]]; then
        local option="${COMP_WORDS[COMP_CWORD-1]}"
        _shm_completion_prepare "${COMP_WORDS[0]}" "$option=" \
            "${COMP_WORDS[@]:1:COMP_CWORD-2}"
        _shm_bash_strip_prefix="$option="
        _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
        return
    fi
    _shm_completion_prepare "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" \
        "${COMP_WORDS[@]:1:COMP_CWORD-1}"
    _shm_completion_apply_suffix "${COMP_WORDS[@]:COMP_CWORD+1}"
}

_shm_completion_repository() {
    _shm_bash_prepare
    _shm_completion_git_repository
}

_shm_local_branches() {
    _shm_bash_prepare
    _shm_kind=available-branch
    _shm_completion_git_candidates
}

_shm_worktree_branches() {
    _shm_bash_prepare
    _shm_kind=worktree-branch
    _shm_completion_git_candidates
}

_shm_bash_executables() {
    local remaining="$PATH" directory candidate last=0 seen=$'\n'
    while :; do
        directory="${remaining%%:*}"
        if [[ "$remaining" == *:* ]]; then remaining="${remaining#*:}"
        else last=1; fi
        directory="${directory:-.}"
        while IFS= read -r candidate; do
            [[ -f "$candidate" && -x "$candidate" ]] || continue
            candidate="${candidate##*/}"
            [[ "$seen" != *$'\n'"$candidate"$'\n'* ]] || continue
            seen+="$candidate"$'\n'
            COMPREPLY+=("$candidate")
        done < <(compgen -f -- "$directory/$_shm_cur")
        [[ "$last" == 0 ]] || break
    done
}

_shm_git_complete() {
    local candidate actual
    COMPREPLY=()
    _shm_bash_prepare
    # No default filename fallback: a missing ID/ref is not a filesystem path.
    compopt +o filenames +o nospace 2>/dev/null || true
    # Readline must quote the literal tools wildcard, not insert an active glob.
    [[ "$_shm_kind" != 'enum:*' ]] || compopt -o filenames 2>/dev/null || true
    case "$_shm_kind" in
        file|directory|executable)
            local flag=-f
            [[ "$_shm_kind" != directory ]] || flag=-d
            if [[ "$_shm_kind" == executable && "$_shm_cur" != */* ]]; then
                _shm_bash_executables
            else
                [[ -n "$_shm_file_base" && -d "$_shm_file_base" ]] || return 0
                while IFS= read -r candidate; do
                    actual="$candidate"
                    [[ "$candidate" == /* ]] || actual="$_shm_file_base/$candidate"
                    [[ "$_shm_kind" != executable || -d "$actual" || -x "$actual" ]] || continue
                    if [[ "$candidate" == /* ]]; then
                        [[ ! -d "$candidate" ]] || candidate+='/'
                    else
                        [[ ! -d "$_shm_file_base/$candidate" ]] || candidate+='/'
                    fi
                    candidate="$_shm_equal_prefix$_shm_path_prefix$candidate"
                    COMPREPLY+=("${candidate#"$_shm_bash_strip_prefix"}")
                done < <(cd -- "$_shm_file_base" && compgen "$flag" -- "$_shm_cur")
                compopt -o filenames 2>/dev/null || true
            fi ;;
        *)
            while IFS= read -r candidate; do
                [[ -n "$candidate" ]] || continue
                case "$_shm_kind" in
                    available-branch|worktree-branch)
                        # Worktree commands accept case-insensitive substrings.
                        if [[ "${candidate,,}" == *"${_shm_cur,,}"* ]]; then
                            COMPREPLY+=("$candidate")
                        fi ;;
                    *)
                        if [[ "$candidate" == "$_shm_cur"* ]]; then
                            candidate="$_shm_equal_prefix$candidate"
                            COMPREPLY+=("${candidate#"$_shm_bash_strip_prefix"}")
                        fi ;;
                esac
            done < <(_shm_completion_candidates) ;;
    esac
    return 0
}

while IFS= read -r _shm_command; do
    complete -F _shm_git_complete "$_shm_command"
done < <(_shm_completion_commands)
unset _shm_command
