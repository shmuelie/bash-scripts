#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export COPILOT_HOME="$WORK/home" DATE_CALLS="$WORK/date-calls"
    mkdir -p "$COPILOT_HOME/session-state" "$WORK/project" "$WORK/other" "$WORK/bin"
    export REAL_DATE
    REAL_DATE="$(command -v date)"
    cat > "$WORK/bin/date" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == +%s.%N ]]; then
    printf 'now\n' >> "$DATE_CALLS"
    printf '1769904000.000000000\n'
else
    exec "$REAL_DATE" "$@"
fi
EOF
    chmod +x "$WORK/bin/date"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    cd "$WORK/project"
}

teardown() {
    cd "$REPO_ROOT"
    rm -rf -- "$WORK"
}

session() {
    local id="$1" updated="$2" cwd="${3-$WORK/project}" repo="${4-owner/repo}" branch="${5-main}" name="${6-Work}"
    local dir="$COPILOT_HOME/session-state/$id"
    mkdir -p "$dir"
    printf 'id: %s\ncwd: %s\nupdated_at: %s\nrepository: %s\nbranch: %s\nname: %s\ncreated_at: 2000-01-01T00:00:00Z\n' \
        "$id" "$cwd" "$updated" "$repo" "$branch" "$name" > "$dir/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$dir/events.jsonl"
}

ids() {
    copilot-session list "$@" --json | jq -r 'map(.id) | join(",")'
}

@test "shared metadata filters compose without broadening default local discovery" {
    session local 2026-01-01T00:00:00Z "$WORK/project" OWNER/Repo feature/local 'Local work'
    session other 2026-01-02T00:00:00Z "$WORK/other" owner/repo feature/other 'Other work'
    session mismatch 2026-01-03T00:00:00Z "$WORK/project" owner/nope feature/nope 'Other work'
    run ids --repository 'owner/re*' --branch 'FEATURE/*' --summary '*work'
    [ "$status" -eq 0 ]
    [ "$output" = local ]
    run ids --all --repository 'owner/re*' --branch 'feature/*' --summary 'other*'
    [ "$output" = other ]
    run ids --cwd "$WORK/oth*" --repository 'OWNER/*'
    [ "$output" = other ]
    run ids --id other
    [ "$output" = other ]
}

@test "metadata wildcards exclude absent fields but summary uses the display fallback" {
    session missing '' '' '' '' ''
    session legacy 2026-01-01T00:00:00Z "$WORK/project" owner/repo main ''
    printf 'summary: Legacy work\n' >> "$COPILOT_HOME/session-state/legacy/workspace.yaml"
    run ids --all --repository '*'
    [ "$output" = legacy ]
    run ids --all --branch '*'
    [ "$output" = legacy ]
    run ids --cwd '*'
    [ "$output" = legacy ]
    run ids --all --summary '(NO SUMMARY)'
    [ "$output" = missing ]
    run ids --all --summary 'legacy*'
    [ "$output" = legacy ]
}

@test "age filters use exclusive normalized instants and exclude missing updates" {
    session before 2026-01-30T23:59:59.999999999Z
    session exact 2026-01-31T02:00:00+02:00
    session after 2026-01-31T00:00:00.000000001Z
    session missing ''
    run ids --older-than 1d --updated-before 2026-01-31T00:00:00Z
    [ "$status" -eq 0 ]
    [ "$output" = before ]
    [ "$(wc -l < "$DATE_CALLS")" -eq 1 ]
    run ids --updated-before 2026-01-31T00:00:00.000000001Z
    [ "$output" = exact,before ]
}

@test "date-only cutoffs use local midnight and mixed offsets sort by instant" {
    session older 2026-01-02T01:00:00+03:00
    session newer 2026-01-01T23:00:00Z
    run env TZ=UTC copilot-session list --updated-before 2026-01-02 --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r 'map(.id) | join(",")')" = newer,older ]
    run env TZ=Etc/GMT-2 copilot-session list --updated-before 2026-01-02 --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
}

@test "global selection applies shared filters before its newest-first limit" {
    session old 2026-01-01T23:00:00Z "$WORK/other" owner/repo feature/old 'Matching work'
    session newer-looking 2026-01-02T01:00:00+03:00 "$WORK/other" owner/repo feature/old 'Matching work'
    session excluded 2026-01-03T00:00:00Z "$WORK/other" owner/repo feature/other 'Other'
    run copilot-session select --repository 'OWNER/*' --branch 'feature/old' \
        --summary 'matching*' --cwd "$WORK/oth*" --updated-before 2026-01-04 \
        --older-than 1d --first 1 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resume Copilot session old from $WORK/other"* ]]
}

@test "invalid age arguments fail before discovery even when no sessions match" {
    local value
    for value in 0d -1d 1 1month 1.5d ''; do
        run copilot-session list --all --older-than "$value" --json
        [ "$status" -ne 0 ]
        [[ "$output" == *"requires"* ]]
    done
    for value in yesterday 2026-02-30 2026-99-01 ''; do
        run copilot-session select --updated-before "$value" --dry-run
        [ "$status" -ne 0 ]
        [[ "$output" == *"requires"* ]]
    done
}

@test "invalid recorded timestamps are reported and never become age matches" {
    session invalid nonsense
    run copilot-session list --all --older-than 1d --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid updated_at"* ]]
    [[ "$output" == *'[]' ]]
}

@test "filtered discovery remains separate from previewable source-root-guarded removal" {
    session old 2026-01-01T00:00:00Z
    session new 2026-02-01T00:00:00Z
    run bash -o pipefail -c 'copilot-session list --all --older-than 1d --json |
        jq -r ".[].id" | while IFS= read -r id; do copilot-session remove "$id" --dry-run; done'
    [ "$status" -eq 0 ]
    [[ "$output" == *"(old)"* ]]
    [[ "$output" != *"(new)"* ]]
    [ -d "$COPILOT_HOME/session-state/old" ]
    [ -d "$COPILOT_HOME/session-state/new" ]
}
