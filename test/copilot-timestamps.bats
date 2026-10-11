#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-timestamps-$$-$BATS_TEST_NUMBER"
    export COPILOT_HOME="$WORK/home" PATH="$REPO_ROOT/bin:$PATH"
    mkdir -p "$COPILOT_HOME/session-state"
}

teardown() { rm -rf -- "$WORK"; }

fixture() {
    local id="$1" created="$2" updated="$3"
    mkdir -p "$COPILOT_HOME/session-state/$id"
    printf 'name: %s\ncwd: %s\ncreated_at: %s\nupdated_at: %s\n' \
        "$id" "$PWD" "$created" "$updated" > "$COPILOT_HOME/session-state/$id/workspace.yaml"
}

@test "malformed creation or update skips only affected sessions with visible field diagnostics" {
    fixture healthy 2026-01-01T00:00:00Z 2026-01-02T00:00:00Z
    fixture bad-created 2026-02-30T00:00:00Z 2026-01-03T00:00:00Z
    fixture bad-updated 2026-01-01T00:00:00Z nonsense
    fixture both broken broken
    run bash -c 'copilot-session list --all --json > "$COPILOT_HOME/list.json"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Session 'bad-created' has invalid created_at"* ]]
    [[ "$output" == *"Session 'bad-updated' has invalid updated_at"* ]]
    [[ "$output" == *"Session 'both' has invalid created_at"* ]]
    [[ "$output" == *"Session 'both' has invalid updated_at"* ]]
    [ "$(jq -r 'map(.id) | join(",")' "$COPILOT_HOME/list.json")" = healthy ]
}

@test "missing optional timestamps stay null and undated without diagnostics or substitution" {
    fixture undated '' ''
    fixture healthy '' 2026-01-01T00:00:00Z
    run copilot-session list --all --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r 'map(.id) | join(",")')" = healthy,undated ]
    printf '%s' "$output" | jq -e '.[1].createdAt == null and .[1].updatedAt == null'
    run copilot-session list --all --older-than 1s --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r 'map(.id) | join(",")')" = healthy ]
}

@test "malformed creation and update never enter either age-filter result" {
    fixture healthy 2020-01-01 2020-01-02
    fixture bad-created invalid 2020-01-01
    fixture bad-updated 2020-01-01 invalid
    fixture undated 2000-01-01 ''
    run bash -c 'copilot-session list --all --updated-before 2025-01-01 --older-than 1d --json > "$COPILOT_HOME/list.json"'
    [ "$status" -eq 0 ]
    [ "$(jq -r 'map(.id) | join(",")' "$COPILOT_HOME/list.json")" = healthy ]
    [[ "$output" == *bad-created* && "$output" == *bad-updated* ]]
}
