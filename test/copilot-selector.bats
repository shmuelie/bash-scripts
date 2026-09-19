#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export COPILOT_HOME="$WORK/home" CANDIDATES="$WORK/candidates" RECORD="$WORK/record"
    mkdir -p "$COPILOT_HOME/session-state" "$WORK/project" "$WORK/other" "$WORK/bin"
    cat > "$WORK/bin/selector" <<'EOF'
#!/usr/bin/env bash
cat > "$CANDIDATES"
[[ "${SELECTOR_STATUS:-0}" == 0 ]] || exit "$SELECTOR_STATUS"
if [[ -n "${SELECTOR_RESULT+x}" ]]; then printf '%s' "$SELECTOR_RESULT"
else jq '{id:.[0].id}' "$CANDIDATES"; fi
EOF
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$@" > "$RECORD"
EOF
    chmod +x "$WORK/bin/selector" "$WORK/bin/copilot"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    cd "$WORK/project"
    git init -q -b main
}

teardown() {
    cd "$REPO_ROOT"
    rm -rf -- "$WORK"
}

session() {
    local id="$1" name="$2" branch="${3-main}" cwd="${4-$WORK/project}"
    local dir="$COPILOT_HOME/session-state/$id"
    mkdir -p "$dir"
    printf 'id: %s\nname: %s\ncwd: %s\nbranch: %s\nrepository: owner/repo\nupdated_at: 2026-01-01T00:00:00Z\n' \
        "$id" "$name" "$cwd" "$branch" > "$dir/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$dir/events.jsonl"
}

@test "selector receives filtered typed candidates and cannot replace original metadata" {
    session selected 'Matching work' feature/one "$WORK/other"
    session wrong 'Other work' feature/two
    export SELECTOR_RESULT='{"id":"selected","cwd":"/not-the-recorded-path","name":"forged"}'
    run copilot-session select --selector selector --repository 'OWNER/*' --branch 'feature/one' \
        --summary 'matching*' --cwd "$WORK/oth*" --older-than 1d --first 1 \
        'continue' -- --model fast
    [ "$status" -eq 0 ]
    run jq -e 'length==1 and .[0].id=="selected" and .[0].name=="Matching work" and
        .[0].branch=="feature/one" and .[0].repository=="owner/repo" and
        .[0].updatedAt=="2026-01-01T00:00:00Z" and .[0].eventCount==1' "$CANDIDATES"
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$RECORD")" = "$WORK/other" ]
    grep -Fxq -- --resume "$RECORD"
    grep -Fxq -- fast "$RECORD"
}

@test "launcher invokes selector only at existing policy picker boundary" {
    session one 'Named'
    run copilot-launch-plan --selector selector --json
    [ "$status" -eq 0 ]
    [ ! -e "$CANDIDATES" ]
    session stub ''
    run copilot-launch-plan --selector selector --json
    [ "$status" -eq 0 ]
    [ ! -e "$CANDIDATES" ]
    session two 'Second'
    session wrong-branch 'Wrong branch' feature/other
    session wrong-folder 'Wrong folder' main "$WORK/other"
    run copilot-launch-plan --selector selector --json
    [ "$status" -eq 0 ]
    run jq -r 'map(.id) | sort | join(",")' "$CANDIDATES"
    [ "$output" = one,two ]
    run copilot-launch-plan --selector selector --include-unnamed --no-auto-resume --json
    [ "$status" -eq 0 ]
    run jq -r 'map(.id) | sort | join(",")' "$CANDIDATES"
    [ "$output" = one,stub,two ]
}

@test "selector decision changes only resume arguments not launch configuration" {
    session one One
    session two Two
    export SELECTOR_RESULT='{"id":"one"}'
    local flags=(--model model --reasoning-effort high --disable-mcp-server local \
        --enable-mcp-server remote --allow-all-tools --name 'New name')
    copilot-launch-plan --resume-session one "${flags[@]}" --json 'work' -- --custom value > "$WORK/expected"
    run copilot-launch-plan --selector selector "${flags[@]}" --json 'work' -- --custom value
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "$WORK/expected")" ]
}

@test "explicit resume latest new session passthrough and dry-run bypass selector" {
    session one One
    session two Two
    export SELECTOR_STATUS=99
    local option
    for option in --resume-latest --no-resume --defer-resume; do
        run copilot-launch-plan --selector selector "$option" --json
        [ "$status" -eq 0 ]
    done
    run copilot-launch-plan --selector selector --resume-session forced --json
    [ "$status" -eq 0 ]
    run copilot-launch-plan --selector selector --session-id explicit --json
    [ "$status" -eq 0 ]
    run copilot-launch-plan --selector selector update --json
    [ "$status" -eq 0 ]
    run start-copilot --selector selector --dry-run
    [ "$status" -eq 0 ]
    run copilot-session select --selector selector --first 1 --dry-run
    [ "$status" -eq 0 ]
    [ ! -e "$CANDIDATES" ]
    [ ! -e "$RECORD" ]
}

@test "selector new and cancellation results have explicit behavior without fallback" {
    session one One
    session two Two
    export SELECTOR_RESULT='{"action":"new"}'
    run copilot-launch-plan --selector selector --name Fresh --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.args | index("--resume")')" = null ]
    [[ "$output" == *Fresh* ]]
    run copilot-session select --selector selector
    [ "$status" -eq 0 ]
    [ "$(head -n1 "$RECORD")" = "$WORK/project" ]
    ! grep -Fxq -- --resume "$RECORD"
    rm "$RECORD"
    export SELECTOR_RESULT='{"action":"cancel"}'
    run start-copilot --selector selector
    [ "$status" -eq 130 ]
    run copilot-session select --selector selector
    [ "$status" -eq 130 ]
    [ ! -e "$RECORD" ]
}

@test "selector malformed unknown identities and execution failures abort instead of launching" {
    session one One
    session two Two
    local result
    for result in '' null '[]' '{"id":"absent"}' '{"id":"one","action":"new"}' \
        '{"action":"unknown"}' '{"id":"one"} {"id":"two"}'; do
        export SELECTOR_RESULT="$result"
        run start-copilot --selector selector
        [ "$status" -ne 0 ]
        [[ "$output" == *"selector"* ]]
        [ ! -e "$RECORD" ]
    done
    export SELECTOR_STATUS=7
    run copilot-launch-plan --selector selector --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"selector failed"* ]]
    run copilot-session select --selector missing-executable
    [ "$status" -ne 0 ]
    [ ! -e "$RECORD" ]
}

@test "empty candidates bypass callback and noninteractive callbacks need no console" {
    run copilot-launch-plan --selector selector --json
    [ "$status" -eq 0 ]
    [ ! -e "$CANDIDATES" ]
    run copilot-session select --selector selector
    [ "$status" -ne 0 ]
    [[ "$output" == *"No Copilot sessions matched"* ]]
    [ ! -e "$CANDIDATES" ]
    session one One
    run bash -c 'copilot-launch-plan --no-auto-resume --selector selector --json </dev/null'
    [ "$status" -eq 0 ]
    [ -e "$CANDIDATES" ]
}
