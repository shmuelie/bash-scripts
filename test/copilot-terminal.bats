#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    command -v cc >/dev/null || skip 'native compiler required for terminal regression'
    command -v python3 >/dev/null || skip 'python3 required for PTY regression'
    command -v tmux >/dev/null || skip 'tmux required for private-server regression'
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/bin" "$WORK/home"
    cc -Wall -Wextra -Werror "$REPO_ROOT/test/copilot-native.c" -o "$WORK/bin/copilot"
}

teardown() {
    [[ -z "${WORK:-}" ]] || rm -rf -- "$WORK"
}

@test "launcher gives native copilot tmux identity and skips recovery on success" {
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" success
    [ "$status" -eq 0 ]
}

@test "launcher runs actual terminal recovery and preserves failure exit status" {
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" failure
    [ "$status" -eq 0 ]
}

@test "launcher Ctrl-C reaps native child and returns terminal ownership" {
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" interrupt
    [ "$status" -eq 0 ]
}

@test "launcher repeated Ctrl-Z and fg resume the same child without premature recovery" {
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" suspend
    [ "$status" -eq 0 ]
}

@test "launcher suspend-resume preserves later normal and failure exits" {
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" suspend-success
    [ "$status" -eq 0 ]
    rm -f "$WORK/terminal-output"
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" suspend-failure
    [ "$status" -eq 0 ]
}

@test "launcher redirected execution preserves exit status without job-control warnings" {
    run python3 "$REPO_ROOT/test/copilot-terminal.py" "$WORK" redirected
    [ "$status" -eq 0 ]
}
