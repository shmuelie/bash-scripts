#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export WORK CALL_LOG="$WORK/calls"
    mkdir "$WORK/bin"
    : > "$CALL_LOG"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
}

teardown() { rm -rf "$WORK"; }

stub() {
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$CALL_LOG"\n%s\n' "$2" > "$WORK/bin/$1"
    chmod +x "$WORK/bin/$1"
}

@test "npm identifiers accept scoped names and the exact 214 character boundary" {
    stub npm 'exit 0'
    name="$(printf '%0214d' 0)"
    run npm-package update "$name" --global
    [ "$status" -eq 0 ]
    run npm-package update @scope/my-package --global
    [ "$status" -eq 0 ]
    grep -qx 'install -g @scope/my-package@latest' "$CALL_LOG"
    run npm-package update "${name}x" --dry-run
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$CALL_LOG")" -eq 2 ]
}

@test "npm rejects unsafe specs before preview or native invocation" {
    stub npm 'exit 0'
    for name in './tool' '--ignore-scripts' '@scope/' '@scope/.tool' 'a@latest' \
        'a;echo' 'https://example.com/a' 'a b' $'a\nb' 'námé'; do
        run npm-package update "$name" --dry-run
        [ "$status" -ne 0 ]
    done
    [ ! -s "$CALL_LOG" ]
    run bash -c 'printf "%s\n" valid --ignore-scripts | npm-package update --global'
    [ "$status" -ne 0 ]
    [ "$(cat "$CALL_LOG")" = 'install -g valid@latest' ]
}

@test "npm outdated accepts exit 1 only with valid inventory and retains fatal exits" {
    stub npm 'echo "{\"@scope/tool\":{\"current\":\"1\",\"latest\":\"2\"}}"; exit 1'
    run npm-package list --outdated --global --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].name' <<< "$output")" = '@scope/tool' ]
    stub npm 'echo native-failure >&2; exit 42'
    run npm-package list --outdated --json
    [ "$status" -eq 42 ]
    [[ "$output" == *native-failure* ]]
    stub npm 'exit 1'
    run npm-package list --outdated --json
    [ "$status" -ne 0 ]
    stub npm 'echo "{\"error\":{\"code\":\"EFAIL\"}}"; exit 1'
    run npm-package list --outdated --json
    [ "$status" -ne 0 ]
}

@test "canonical Python and dotnet updates preserve native failure status" {
    for tool in pip uv dotnet; do stub "$tool" 'echo native-failure >&2; exit 42'; done
    for command in pip-package uv-package dotnet-tool; do
        run "$command" update demo
        [ "$status" -eq 42 ]
        [[ "$output" == *native-failure* ]]
    done
}

@test "dotnet and VS Code failed inventory cannot become empty success" {
    for tool in dotnet code; do stub "$tool" 'echo native-failure >&2; exit 42'; done
    for command in dotnet-tool vscode-ext; do
        run "$command" list --json
        [ "$status" -eq 42 ]
        [[ "$output" == *native-failure* ]]
    done
}

@test "uv failed top-level discovery and unrecognized tool inventory fail" {
    stub uv 'case "$2" in list) echo "[{\"name\":\"demo\",\"version\":\"1\"}]";; show) exit 42;; esac'
    run uv-package list --top-level --json
    [ "$status" -eq 42 ]
    stub uv 'echo "unrecognized native output"'
    run uv-tool list --json
    [ "$status" -ne 0 ]
}

@test "uv upgrades tools rather than reinstalling them" {
    stub uv 'exit 0'
    run uv-tool update demo
    [ "$status" -eq 0 ]
    [ "$(cat "$CALL_LOG")" = 'tool upgrade demo' ]
    : > "$CALL_LOG"
    run uv-tool update demo --dry-run
    [ "$status" -eq 0 ]
    [ ! -s "$CALL_LOG" ]
}

@test "VS Code bulk previews never mutate and updates forward the profile" {
    stub code 'exit 0'
    run vscode-ext update --dry-run --profile 'Work Space'
    [ "$status" -eq 0 ]
    [ ! -s "$CALL_LOG" ]
    run vscode-ext update --profile 'Work Space'
    [ "$status" -eq 0 ]
    [ "$(cat "$CALL_LOG")" = '--update-extensions --profile Work Space' ]
    : > "$CALL_LOG"
    for profile in '--new-window' '' 'Work&Other' $'Work\nOther'; do
        run vscode-ext update --profile "$profile"
        [ "$status" -ne 0 ]
    done
    run vscode-ext update --unexpected
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
}
