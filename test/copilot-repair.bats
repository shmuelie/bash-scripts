#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export COPILOT_HOME="$WORK/home"
    export PATH="$REPO_ROOT/bin:$PATH"
    D="$COPILOT_HOME/session-state/repair"
    mkdir -p "$D"
    printf 'id: repair\ncwd: /synthetic/project\nname: Repair\n' > "$D/workspace.yaml"
}

teardown() {
    rm -rf -- "$WORK"
}

fixture() {
    local position="$1" invalid="$2"
    {
        printf '{"type":"session.start","id":"s","data":{"sessionId":"repair"}}\n'
        printf '{"type":"user.message","id":"u","data":{}}\n'
        printf '{"type":"session.warning","id":"warning"}\n'
        printf '{"type":"tool.execution_start","id":"","data":{"toolCallId":"bad"}}\n'
        [[ "$position" != before ]] || printf '%s\n' "$invalid"
        printf '%s\n' '{ "type": "tool.execution_start", "id": "valid-start", "data": {"toolCallId":"valid"} }'
        printf '%s\n' '{ "type": "tool.execution_complete", "id": "valid-complete", "data": {"toolCallId":"valid","model":"known","success":false,"result":{"content":"original failure"}} }'
        printf '{"type":"assistant.message","id":"a","data":{"model":"known","toolRequests":[{"toolCallId":"bad"},{"toolCallId":"valid"}]}}\n'
        [[ "$position" != after ]] || printf '%s\n' "$invalid"
        printf '{"type":"assistant.turn_end","id":"end","timestamp":"2026-01-01T00:00:00Z"}\n'
    } > "$D/events.jsonl"
}

assert_repaired() {
    local file="$1"
    run jq -s '[.[] | select(.id=="" or (.type=="tool.execution_complete" and .data.model=="unknown"))] | length' "$file"
    [ "$output" = 0 ]
    run jq -s '[.[] | select(.type=="tool.execution_complete" and .data.toolCallId=="bad")] | length' "$file"
    [ "$output" = 1 ]
    grep -Fxq '{ "type": "tool.execution_start", "id": "valid-start", "data": {"toolCallId":"valid"} }' <(tr -d '\r' < "$file")
    grep -Fxq '{ "type": "tool.execution_complete", "id": "valid-complete", "data": {"toolCallId":"valid","model":"known","success":false,"result":{"content":"original failure"}} }' <(tr -d '\r' < "$file")
    run jq -sr 'map(.id) | index("a") < index("valid-start") and index("valid-start") < index("valid-complete")' "$file"
    [ "$output" = true ]
}

@test "repair prefilters malformed completions in either order and is one-pass idempotent" {
    local invalid position
    for invalid in \
        '{"type":"tool.execution_complete","id":"","data":{"toolCallId":"bad","model":"known"}}' \
        '{"type":"tool.execution_complete","id":"invalid","data":{"toolCallId":"bad","model":"unknown"}}'; do
        for position in before after; do
            fixture "$position" "$invalid"
            cp "$D/events.jsonl" "$WORK/original"
            run copilot-session-maintenance repair-events repair
            [ "$status" -eq 0 ]
            cmp "$WORK/original" "$D/events.jsonl.bak"
            assert_repaired "$D/events.jsonl"
            cp "$D/events.jsonl" "$WORK/repaired"
            run copilot-session-maintenance repair-events repair --no-backup
            [ "$status" -eq 0 ]
            cmp "$WORK/repaired" "$D/events.jsonl"
        done
    done
}

@test "compress and merge use the same retained-array relocation indexes" {
    fixture before '{"type":"tool.execution_complete","id":"","data":{"toolCallId":"bad","model":"unknown"}}'
    cp "$D/events.jsonl" "$WORK/original"
    run copilot-session-maintenance compress repair --keep 1
    [ "$status" -eq 0 ]
    cmp "$WORK/original" "$D/events.jsonl.bak"
    assert_repaired "$D/events.jsonl"
    cp "$WORK/original" "$D/events.jsonl"
    local other="$COPILOT_HOME/session-state/other"
    mkdir -p "$other"
    printf 'id: other\ncwd: /synthetic/project\nname: Other\n' > "$other/workspace.yaml"
    printf '{"type":"session.start","id":"other","data":{"sessionId":"other"}}\n' > "$other/events.jsonl"
    run copilot-session-maintenance merge repair other
    [ "$status" -eq 0 ]
    local merged="$COPILOT_HOME/session-state/${lines[-1]}/events.jsonl"
    assert_repaired "$merged"
    cmp "$WORK/original" "$D/events.jsonl"
}
