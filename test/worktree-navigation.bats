#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export REPO_ROOT WORK HOME="$WORK/home"
    export PATH="$REPO_ROOT/bin:$PATH"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
    export GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_EMAIL=test@example.com
    mkdir -p "$HOME" "$WORK/caller" "$WORK/repos/org/project"
    git init -q -b main "$WORK/repos/org/project/main"
    git -C "$WORK/repos/org/project/main" commit -qm seed --allow-empty
    repo="$WORK/repos/org/project/main"
    export NAV_REPO="$repo" SHELL=/bin/bash
    cd "$WORK/caller"
}

teardown() {
    cd "$REPO_ROOT"
    rm -rf -- "$WORK"
}

interactive() {
    local shell="$1"; shift
    if [[ "$shell" == bash ]]; then
        run --separate-stderr bash --noprofile --norc -ic "$*" --
    else
        command -v zsh >/dev/null || skip 'zsh is not installed'
        run --separate-stderr zsh -fic "$*" --
    fi
}

@test "same-name wrappers create new worktrees and enter them in Bash and zsh" {
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT" || exit
            git-worktree-new -C "$NAV_REPO" --no-prefix --worktree-path "$WORK/new worktree" topic || exit
            [[ "$PWD" == "$WORK/new worktree" ]] || exit 91
        '
        [ "$status" -eq 0 ]
        [ "$output" = "$WORK/new worktree" ]
        git -C "$repo" worktree remove "$WORK/new worktree"
        git -C "$repo" branch -D topic >/dev/null
    done
}

@test "existing branch wrappers resolve relative destinations from the repository not the caller" {
    git -C "$repo" branch topic
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT" || exit
            git-worktree-add -C "$NAV_REPO" --worktree-path "../existing worktree" topic || exit
            [[ "$PWD" == "$WORK/repos/org/project/existing worktree" ]] || exit 91
        '
        [ "$status" -eq 0 ]
        [ "$output" = "$WORK/repos/org/project/existing worktree" ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/existing worktree"
    done
}

@test "per-call opt-out and command bypass preserve stdout and caller directory" {
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT" || exit
            caller="$PWD"
            git-worktree-new -C "$NAV_REPO" --no-prefix --stay-in-directory topic || exit
            [[ "$PWD" == "$caller" ]] || exit 91
            command git-worktree-new -C "$NAV_REPO" --no-prefix other || exit
            [[ "$PWD" == "$caller" ]] || exit 92
        '
        [ "$status" -eq 0 ]
        [ "$output" = "$WORK/repos/org/project/topic"$'\n'"$WORK/repos/org/project/other" ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/topic"
        git -C "$repo" worktree remove "$WORK/repos/org/project/other"
        git -C "$repo" branch -D topic other >/dev/null
    done
}

@test "preview declined confirmation help and failures never navigate or fabricate destinations" {
    git -C "$repo" branch topic
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT" || exit
            caller="$PWD"
            git-worktree-new -C "$NAV_REPO" --no-prefix --dry-run new || exit
            git-worktree-add -C "$NAV_REPO" --whatif topic || exit
            git-worktree-new -C "$NAV_REPO" --no-prefix --confirm declined < /dev/null || exit
            git-worktree-add -C "$NAV_REPO" --confirm topic < /dev/null || exit
            git-worktree-new --help > "$WORK/help" || exit
            git-worktree-add -C "$NAV_REPO" missing > "$WORK/failure" && exit 91
            [[ "$PWD" == "$caller" ]] || exit 92
            [[ ! -s "$WORK/failure" ]] || exit 93
            [[ ! -d "$WORK/repos/org/project/new" && ! -d "$WORK/repos/org/project/declined" ]] || exit 94
        '
        [ "$status" -eq 0 ]
        [ -z "$output" ]
        [[ "$stderr" == *'What if:'* && "$stderr" == *Declined:* && "$stderr" == *'failed'* ]]
    done
}

@test "option-like values are literal and do not disable or trigger navigation" {
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT" || exit
            git-worktree-new -C "$NAV_REPO" --kind user --user --help task || exit
            [[ "$PWD" == "$WORK/repos/org/project/user/--help/task" ]] || exit 91
        '
        [ "$status" -eq 0 ]
        [ "$output" = "$WORK/repos/org/project/user/--help/task" ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/user/--help/task"
        git -C "$repo" branch -D user/--help/task >/dev/null
    done
}

@test "approved worktree creation navigates while retaining stdin-based confirmation" {
    printf 'y\n' > "$WORK/approval"
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT" || exit
            git-worktree-new -C "$NAV_REPO" --no-prefix --confirm topic < "$WORK/approval" || exit
            [[ "$PWD" == "$WORK/repos/org/project/topic" ]]
        '
        [ "$status" -eq 0 ]
        [ "$output" = "$WORK/repos/org/project/topic" ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/topic"
        git -C "$repo" branch -D topic >/dev/null
    done
}

@test "noninteractive sourcing does not define wrappers or change executable behavior" {
    for shell in bash zsh; do
        if [[ "$shell" == bash ]]; then
            run --separate-stderr bash --noprofile --norc -c '
                source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT"
                declare -F git-worktree-new && exit 91
                caller="$PWD"
                git-worktree-new -C "$NAV_REPO" --no-prefix topic || exit
                [[ "$PWD" == "$caller" ]]
            '
        else
            command -v zsh >/dev/null || skip 'zsh is not installed'
            run --separate-stderr zsh -fc '
                source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$REPO_ROOT"
                [[ -z "${functions[git-worktree-new]:-}" ]] || exit 91
                caller="$PWD"
                git-worktree-new -C "$NAV_REPO" --no-prefix topic || exit
                [[ "$PWD" == "$caller" ]]
            '
        fi
        [ "$status" -eq 0 ]
        [ "$output" = "$WORK/repos/org/project/topic" ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/topic"
        git -C "$repo" branch -D topic >/dev/null
    done
}

@test "wrapper propagates native exit status and rejects success with invalid output before cd" {
    mkdir -p "$WORK/fake/bin" "$WORK/fake/lib"
    cat > "$WORK/fake/bin/git-worktree-new" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${FAKE_OUTPUT:-}"
exit "${FAKE_EXIT:-0}"
EOF
    chmod +x "$WORK/fake/bin/git-worktree-new"
    for shell in bash zsh; do
        interactive "$shell" '
            source "$REPO_ROOT/lib/git/worktree-navigation.sh" "$WORK/fake" || exit
            caller="$PWD"
            export FAKE_EXIT=42 FAKE_OUTPUT="partial output"
            exit_code=0; git-worktree-new || exit_code=$?
            [[ "$exit_code" == 42 && "$PWD" == "$caller" ]] || exit 91
            export FAKE_EXIT=0 FAKE_OUTPUT="$WORK/missing"
            git-worktree-new && exit 92
            export FAKE_OUTPUT=""
            git-worktree-new || exit
            [[ "$PWD" == "$caller" ]]
        '
        [ "$status" -eq 0 ]
        [ -z "$output" ]
        [[ "$stderr" == *'partial output'* && "$stderr" == *'existing absolute'* ]]
    done
}

@test "installer activates navigation only in interactive shells and disables it independently" {
    local rc="$WORK/rc"
    for shell in bash zsh; do
        export SHELL="/bin/$shell"
        "$REPO_ROOT/install.sh" --prefix "$WORK/bin" --rc "$rc" --no-completions >/dev/null
        "$REPO_ROOT/install.sh" --prefix "$WORK/bin" --rc "$rc" --no-completions >/dev/null
        [ "$(grep -c '^# >>> bash-scripts >>>' "$rc")" -eq 1 ]
        export NAV_RC="$rc"
        interactive "$shell" '
            source "$NAV_RC"; source "$NAV_RC"
            git-worktree-new -C "$NAV_REPO" --no-prefix topic || exit
            [[ "$PWD" == "$WORK/repos/org/project/topic" ]]
        '
        [ "$status" -eq 0 ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/topic"
        git -C "$repo" branch -D topic >/dev/null
        "$REPO_ROOT/install.sh" --prefix "$WORK/bin" --rc "$rc" --no-completions --no-worktree-navigation >/dev/null
        ! grep -q 'worktree-navigation.sh' "$rc"
        interactive "$shell" '
            source "$NAV_RC"
            caller="$PWD"
            git-worktree-new -C "$NAV_REPO" --no-prefix topic || exit
            [[ "$PWD" == "$caller" ]]
        '
        [ "$status" -eq 0 ]
        git -C "$repo" worktree remove "$WORK/repos/org/project/topic"
        git -C "$repo" branch -D topic >/dev/null
        "$REPO_ROOT/install.sh" --prefix "$WORK/bin" --rc "$rc" --no-completions >/dev/null
        "$REPO_ROOT/install.sh" --prefix "$WORK/bin" --rc "$rc" --uninstall >/dev/null
        ! grep -q 'worktree-navigation.sh' "$rc"
    done
}

@test "quick-install bootstrap forwards the navigation opt-out without remote calls" {
    mkdir -p "$WORK/stub" "$WORK/data"
    cat > "$WORK/stub/git" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == clone ]] || exit 91
for argument in "$@"; do target="$argument"; done
mkdir -p "$target"
cp "$REPO_ROOT/install.sh" "$target/install.sh"
ln -s "$REPO_ROOT/bin" "$target/bin"
ln -s "$REPO_ROOT/lib" "$target/lib"
ln -s "$REPO_ROOT/completions" "$target/completions"
EOF
    chmod +x "$WORK/stub/git"
    run --separate-stderr bash -c '
        cat "$REPO_ROOT/install.sh" |
        PATH="$WORK/stub:$PATH" XDG_DATA_HOME="$WORK/data" bash -s -- \
            --no-worktree-navigation --no-completions --prefix "$WORK/bin" --rc "$WORK/bootstrap.rc"
    '
    [ "$status" -eq 0 ]
    [ -L "$WORK/bin/git-worktree-new" ]
    [ ! -e "$WORK/bootstrap.rc" ]
}
