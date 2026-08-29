#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    WORK="$REPO_ROOT/.test-work-format-${BATS_TEST_NUMBER:-0}-$$"
    rm -rf "$WORK"
    mkdir -p "$WORK"

    git init -q -b main "$WORK/repo"
    git -C "$WORK/repo" config user.email dev@example.com
    git -C "$WORK/repo" config user.name Dev
    printf 'base\n' > "$WORK/repo/tracked.txt"
    git -C "$WORK/repo" add tracked.txt
    git -C "$WORK/repo" commit -qm init
}

teardown() {
    rm -rf "$WORK"
}

@test "format-duration formats seconds below a minute" {
    run format-duration 5.3004
    [ "$status" -eq 0 ]
    [ "$output" = "5.3 seconds" ]

    run format-duration 59.999
    [ "$output" = "59.999 seconds" ]
}

@test "format-duration formats minute and hour boundaries" {
    run format-duration 60
    [ "$output" = "1:00.000" ]

    run format-duration 3599.999
    [ "$output" = "59:59.999" ]

    run format-duration 3599.9999
    [ "$output" = "59:59.999" ]

    run format-duration 3600
    [ "$output" = "1:00:00.000" ]

    run format-duration 90061.007
    [ "$output" = "25:01:01.007" ]
}

@test "format-duration supports millisecond input and rejects invalid values" {
    run format-duration --milliseconds 61005
    [ "$status" -eq 0 ]
    [ "$output" = "1:01.005" ]

    run format-duration -1
    [ "$status" -ne 0 ]

    run format-duration nope
    [ "$status" -ne 0 ]
}

@test "git-status-segment no-color output folds untracked into working added" {
    printf 'changed\n' >> "$WORK/repo/tracked.txt"
    printf 'new\n' > "$WORK/repo/new.txt"
    git -C "$WORK/repo" add tracked.txt

    run git-status-segment --no-color "$WORK/repo"
    [ "$status" -eq 0 ]
    [ "$output" = "[main +0 ~1 -0 | +1 ~0 -0]" ]
}

@test "git-status-segment compact mode omits all change counts" {
    printf 'new\n' > "$WORK/repo/new.txt"
    run git-status-segment --no-color --no-change-counts "$WORK/repo"
    [ "$status" -eq 0 ]
    [ "$output" = "[main]" ]
}

@test "git-status-segment emits bounded ANSI sequences when enabled" {
    run git-status-segment "$WORK/repo"
    [ "$status" -eq 0 ]
    [ "$output" = $'\033[93m[\033[96mmain\033[93m]\033[0m' ]
    [[ "$output" == $'\033[93m['* ]]
    [[ "$output" == *$']\033[0m' ]]
}

@test "git-status-segment --ps1 marks ANSI as non-printing" {
    run git-status-segment --ps1 "$WORK/repo"
    [ "$status" -eq 0 ]
    [[ "$output" == $'\001\033[93m\002['* ]]
    [[ "$output" == *$'\001\033[0m\002' ]]
}

@test "git-status-segment renders diverged relation down then up" {
    git clone -q --bare "$WORK/repo" "$WORK/remote.git"
    git -C "$WORK/repo" remote add origin "$WORK/remote.git"
    git -C "$WORK/repo" fetch -q origin
    git -C "$WORK/repo" branch --set-upstream-to origin/main main
    git -C "$WORK/repo" commit -q --allow-empty -m local
    git clone -q "$WORK/remote.git" "$WORK/other"
    git -C "$WORK/other" config user.email dev@example.com
    git -C "$WORK/other" config user.name Dev
    git -C "$WORK/other" commit -q --allow-empty -m remote
    git -C "$WORK/other" push -q origin main
    git -C "$WORK/repo" fetch -q origin

    run git-status-segment --no-color --no-change-counts "$WORK/repo"
    [ "$status" -eq 0 ]
    [ "$output" = "[main ↓1 ↑1]" ]
}

@test "git-status-segment is empty outside a repository" {
    run env GIT_CEILING_DIRECTORIES="$REPO_ROOT" git-status-segment "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
