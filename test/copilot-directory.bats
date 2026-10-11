#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-directory-$$-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/home/session-state" "$WORK/caller" "$WORK/target/local" "$WORK/bin"
    export COPILOT_HOME="$WORK/home" RECORD="$WORK/record" CANDIDATES="$WORK/candidates"
    export GIT_CEILING_DIRECTORIES="$WORK"
    cat > "$WORK/target/local/copilot" <<'EOF'
#!/usr/bin/env bash
original="$PWD"
while [[ $# -gt 0 ]]; do
    case "$1" in -C|--change-dir) cd -- "$2"; shift 2 ;; *) shift ;; esac
done
printf '%s\n%s\n' "$original" "$PWD" > "$RECORD"
EOF
    cat > "$WORK/bin/selector" <<'EOF'
#!/usr/bin/env bash
cat > "$CANDIDATES"
printf '%s\n' "$PWD" > "$RECORD"
printf '%s' "$SELECTOR_RESULT"
EOF
    chmod +x "$WORK/target/local/copilot" "$WORK/bin/selector"
    export PATH="./local:$WORK/bin:$REPO_ROOT/bin:$PATH"
    cd "$WORK/target"
    git init -q -b feature
    git remote add origin https://github.com/owner/target
    cd "$WORK/caller"
    git init -q -b main
    git remote add origin https://github.com/owner/caller
}

teardown() { cd "$REPO_ROOT"; rm -rf -- "$WORK"; }

fixture() {
    local id="$1" repo="$2" branch="$3" cwd="$4"
    mkdir -p "$COPILOT_HOME/session-state/$id"
    printf 'name: %s\nrepository: %s\nbranch: %s\ncwd: %s\nupdated_at: 2026-01-01T00:00:00Z\n' \
        "$id" "$repo" "$branch" "$cwd" > "$COPILOT_HOME/session-state/$id/workspace.yaml"
}

@test "relative target scopes selection branch executable and MCP and serializes absolute native directory" {
    fixture one owner/target feature /moved/target
    fixture caller owner/caller main "$PWD"
    printf '{"mcpServers":{"target":{"autoConnect":["%s"]},"caller":{"autoConnect":["%s"]}}}' \
        "$WORK/target" "$WORK/caller" > "$COPILOT_HOME/mcp-config.json"
    run copilot-launch-plan -C ../target --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e --arg cwd "$WORK/target" '
        .cwd == $cwd and .exe == ($cwd+"/local/copilot") and
        (.args | index("one")) != null and
        (.args | index("caller")) != null and (.args | index("target")) == null and
        (.args | index("-C")) != null and (.args | index($cwd)) != null'
    [ "$PWD" = "$WORK/caller" ]
    run start-copilot --change-dir ../target --resume-latest
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$RECORD")" = "$WORK/caller" ]
    [ "$(tail -n1 "$RECORD")" = "$WORK/target" ]
}

@test "callback selection runs in effective directory and cancellation restores caller state" {
    fixture one owner/target feature /moved/target
    fixture two owner/target feature /moved/target
    export SELECTOR_RESULT='{"id":"one"}'
    run copilot-launch-plan --change-dir=../target --selector selector --json
    [ "$status" -eq 0 ]
    [ "$(cat "$RECORD")" = "$WORK/target" ]
    [ "$(jq -r 'map(.id)|join(",")' "$CANDIDATES")" = one,two ]
    export SELECTOR_RESULT='{"action":"cancel"}'
    source "$REPO_ROOT/lib/common.sh"
    source "$REPO_ROOT/lib/copilot/copilot-common.sh"
    source "$REPO_ROOT/lib/copilot/launch-plan.sh"
    local rc=0
    build_launch_plan -C ../target --selector selector || rc=$?
    [ "$rc" -eq 130 ]
    [ "$PWD" = "$WORK/caller" ]
    export SELECTOR_RESULT='{"id":"absent"}'
    rc=0
    build_launch_plan -C ../target --selector selector || rc=$?
    [ "$rc" -eq 1 ]
    [ "$PWD" = "$WORK/caller" ]
}

@test "invalid targets abort before executable resolution and never change caller" {
    source "$REPO_ROOT/lib/common.sh"
    source "$REPO_ROOT/lib/copilot/copilot-common.sh"
    source "$REPO_ROOT/lib/copilot/launch-plan.sh"
    printf file > "$WORK/not-a-directory"
    local value rc
    for value in '' ../missing ../not-a-directory; do
        rc=0
        build_launch_plan -C "$value" || rc=$?
        [ "$rc" -eq 1 ]
        [ "$PWD" = "$WORK/caller" ]
        [ ! -e "$RECORD" ]
    done
}

@test "preview explicit and bypass policies stay scoped without selection or launches" {
    fixture one owner/target feature /old
    fixture two owner/target feature /old
    export SELECTOR_RESULT=invalid
    run start-copilot --dry-run -C ../target --selector selector
    [ "$status" -eq 0 ]
    [[ "$output" == *"$WORK/target"* ]]
    [ ! -e "$RECORD" ]
    local flag
    for flag in --no-resume --defer-resume; do
        run copilot-launch-plan -C ../target "$flag" --selector selector --json
        [ "$status" -eq 0 ]
    done
    run copilot-launch-plan -C ../target --resume-session explicit --selector selector --json
    [ "$status" -eq 0 ]
    [[ "$output" == *explicit* ]]
    [ ! -e "$RECORD" ]
}

@test "help and update keep passthrough directory spelling without applying it twice" {
    run copilot-launch-plan -C ../target update --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.args|join("|")')" = 'update|-C|../target' ]
    run start-copilot -C ../target update
    [ "$status" -eq 0 ]
    [ "$(tail -n1 "$RECORD")" = "$WORK/target" ]
}

@test "repeated directory options choose last target resolved once against caller" {
    run copilot-launch-plan -C ../missing --change-dir ../target --no-resume --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e --arg cwd "$WORK/target" '
        [.args[] | select(.=="-C" or .=="--change-dir")] == ["--change-dir"] and
        ([.args[] | select(.==$cwd)]|length)==1'
}
