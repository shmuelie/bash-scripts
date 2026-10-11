#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/completion-install"
    mkdir -p "$WORK/home"
    export REPO_ROOT WORK
    export HOME="$WORK/home" COPILOT_HOME="$WORK/home/copilot" SHELL=/bin/bash
    PREFIX="$WORK/bin"
    RC="$WORK/shell.rc"
}

install_commands() {
    "$REPO_ROOT/install.sh" --prefix "$PREFIX" --rc "$RC" "$@" > "$WORK/install.log" 2>&1
}

@test "installer activates all Bash registrations in a fresh shell" {
    install_commands
    run bash --noprofile --norc -c '
        source "$1"
        for file in "$REPO_ROOT"/bin/*; do complete -p "${file##*/}" >/dev/null || exit; done
        COMP_WORDS=(package-update --provider np); COMP_CWORD=2
        _shm_git_complete
        printf "%s\n" "${COMPREPLY[@]}"
    ' -- "$RC"
    [ "$status" -eq 0 ]
    [ "$output" = npm ]
}

@test "Bash fresh shell inserts real subcommands, flags, enum values and quoted paths" {
    install_commands
    run python3 "$REPO_ROOT/test/completion-zsh.py" "$REPO_ROOT" "$WORK" "$RC" bash
    [ "$status" -eq 0 ]
    [ "$output" = 'bash completion: 15 cases passed' ]
}

@test "installer activates zsh compinit discovery and actual autoload for every bin" {
    export SHELL=/bin/zsh
    install_commands
    command -v zsh >/dev/null || skip 'zsh is not installed'
    run zsh -f -c '
        source "$REPO_ROOT/test/completion-zsh-env.zsh"
        source "$1"
        for file in "$REPO_ROOT"/bin/*; do
            [[ "${_comps[${file:t}]}" == _shm_commands ]] || exit 1
        done
        autoload +X _shm_commands || exit
        _SHM_COMPLETION_LOAD_ONLY=1
        _shm_commands
        unset _SHM_COMPLETION_LOAD_ONLY
        words=(package-update --provider np); CURRENT=3
        compadd() { shift; print -rl -- "$@"; }
        _shm_zsh_context
    ' -- "$RC"
    [ "$status" -eq 0 ]
    [[ "$output" == npm$'\n'* ]]
}

@test "zsh installation works both before and after another compinit and is source-idempotent" {
    export SHELL=/bin/zsh
    install_commands
    command -v zsh >/dev/null || skip 'zsh is not installed'
    run zsh -f -c '
        source "$REPO_ROOT/test/completion-zsh-env.zsh"
        autoload -Uz compinit; compinit -i -D
        source "$1"; source "$1"
        [[ "${_comps[copilot-session]}" == _shm_commands ]] || exit
        local count=0 directory
        for directory in "$fpath[@]"; do
            [[ "$directory" != "$REPO_ROOT/completions/zsh" ]] || ((count+=1))
        done
        [[ "$count" == 1 ]] || exit 2
        compinit -i -D
        [[ "${_comps[dotnet-sdk-install]}" == _shm_commands ]] || exit 3
    ' -- "$RC"
    [ "$status" -eq 0 ]
    [ ! -f "$HOME/.zcompdump" ]
}

@test "zsh fresh shell inserts real subcommands, flags, enum values and quoted paths" {
    export SHELL=/bin/zsh
    install_commands
    command -v zsh >/dev/null || skip 'zsh is not installed'
    run python3 "$REPO_ROOT/test/completion-zsh.py" "$REPO_ROOT" "$WORK" "$RC"
    [ "$status" -eq 0 ]
    [ "$output" = 'zsh completion: 15 cases passed' ]
}

@test "reinstall is idempotent and preserves unrelated rc bytes and permissions" {
    printf '# keep me\n\n\n' > "$RC"
    chmod 640 "$RC"
    install_commands
    install_commands
    [ "$(grep -cF '# >>> bash-scripts >>>' "$RC")" = 1 ]
    [ "$(stat -c '%a' "$RC")" = 640 ]
    install_commands --uninstall
    run bash -c 'cmp "$1" <(printf "# keep me\n\n\n")' -- "$RC"
    [ "$status" -eq 0 ]
}

@test "no-completions on reinstall removes activation in both shells" {
    for shell in /bin/bash /bin/zsh; do
        export SHELL="$shell"
        install_commands
        install_commands --no-completions --no-worktree-navigation
        ! grep -qF bash-scripts "$RC"
        if [[ "$shell" == /bin/bash ]]; then
            run bash --noprofile --norc -c 'source "$1"; complete -p copilot-session' -- "$RC"
            [ "$status" -ne 0 ]
        else
            command -v zsh >/dev/null || skip 'zsh is not installed'
            run zsh -f -c '
                source "$REPO_ROOT/test/completion-zsh-env.zsh"
                source "$1"
                autoload -Uz compinit; compinit -i -D
                [[ -z "${_comps[copilot-session]:-}" ]]
            ' -- "$RC"
            [ "$status" -eq 0 ]
        fi
        [ -L "$PREFIX/copilot-session" ]
    done
}

@test "path installation retains PATH but omits completions when disabled" {
    install_commands --method path
    install_commands --method path --no-completions --no-worktree-navigation
    run bash --noprofile --norc -c 'source "$1"; command -v copilot-session; complete -p copilot-session' -- "$RC"
    [ "$status" -ne 0 ]
    [ "${lines[0]}" = "$REPO_ROOT/bin/copilot-session" ]
    grep -qF 'export PATH=' "$RC"
    ! grep -qE 'source |compinit|fpath=' "$RC"
}

@test "uninstall removes shell activation and only this repository's links" {
    for shell in /bin/bash /bin/zsh; do
        export SHELL="$shell"
        install_commands
        ln -sf /bin/true "$PREFIX/unrelated"
        install_commands --uninstall
        [ -L "$PREFIX/unrelated" ]
        [ ! -L "$PREFIX/copilot-session" ]
        ! grep -qF bash-scripts "$RC"
        ! grep -qF compinit "$RC"
    done
}

@test "rc activation treats repository paths containing spaces and shell syntax literally" {
    local clone="$WORK/clone space \$(touch SHOULD_NOT_EXIST)"
    mkdir -p "$clone"
    cp "$REPO_ROOT/install.sh" "$clone/"
    ln -s "$REPO_ROOT/bin" "$clone/bin"
    ln -s "$REPO_ROOT/lib" "$clone/lib"
    ln -s "$REPO_ROOT/completions" "$clone/completions"
    for shell in /bin/bash /bin/zsh; do
        export SHELL="$shell"
        "$clone/install.sh" --method path --rc "$RC" > "$WORK/install.log" 2>&1
        if [[ "$shell" == /bin/bash ]]; then
            run bash --noprofile --norc -c '
                source "$1"
                complete -p copilot-session >/dev/null
                [[ "$PATH" == "$2/bin:"* ]]
            ' -- "$RC" "$clone"
        else
            command -v zsh >/dev/null || skip 'zsh is not installed'
            run zsh -f -c '
                source "$REPO_ROOT/test/completion-zsh-env.zsh"
                source "$1"
                [[ "${_comps[copilot-session]}" == _shm_commands ]] || exit
                [[ "$PATH" == "$2/bin:"* ]]
            ' -- "$RC" "$clone"
        fi
        [ "$status" -eq 0 ]
    done
    [ ! -e SHOULD_NOT_EXIST ]
}
