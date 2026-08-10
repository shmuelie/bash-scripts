#!/usr/bin/env bats
# copilot.bats — functional tests for the copilot-* commands. Uses a fake
# COPILOT_HOME and a stub `copilot` executable so nothing external is launched.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    WORK="$(mktemp -d)"
    export WORK
    export COPILOT_HOME="$WORK/.copilot"
    mkdir -p "$COPILOT_HOME/session-state"

    # Stub copilot executable that records its argv and emits canned output.
    STUB="$WORK/stub"
    mkdir -p "$STUB"
    cat > "$STUB/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COPILOT_ARGS_LOG"
case "$1 $2" in
  "plugin list") printf '  • dotnet-skills@dotnet-agent-skills (v1.2.3)\n  • local-plugin (v0.1.0)\n' ;;
  "plugin marketplace")
    case "$3" in
      list) printf '  ◆ dotnet-agent-skills (GitHub: dotnet/skills)\n  • community (URL: https://example.com/mp.json)\n' ;;
      browse) printf '  • alpha - First plugin\n  • beta - Second plugin\n' ;;
    esac ;;
  "mcp list") printf '{"mcpServers":{"ctx7":{"type":"http","url":"https://mcp.context7.com/mcp","source":"user"},"local":{"type":"stdio","command":"npx","args":["-y","@x/y"],"source":"workspace"}}}\n' ;;
esac
exit 0
EOF
    chmod +x "$STUB/copilot"
    export COPILOT_ARGS_LOG="$WORK/copilot-args.log"
    : > "$COPILOT_ARGS_LOG"

    export PATH="$STUB:$REPO_ROOT/bin:$PATH"

    SESSION_CWD="$WORK/proj"
    mkdir -p "$SESSION_CWD"
}

teardown() {
    rm -rf "$WORK"
}

# make_session ID NAME UPDATED BRANCH — create a session dir under COPILOT_HOME.
make_session() {
    local id="$1" name="$2" updated="$3" branch="$4"
    local d="$COPILOT_HOME/session-state/$id"
    mkdir -p "$d"
    {
        echo "id: $id"
        echo "cwd: $SESSION_CWD"
        echo "updated_at: $updated"
        echo "branch: $branch"
        [[ -n "$name" ]] && echo "name: $name"
    } > "$d/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$d/events.jsonl"
}

# ---- launch plan ---------------------------------------------------------

@test "launch-plan applies default flags and deny rules" {
    run bash -c "cd '$WORK' && copilot-launch-plan --no-resume --json"
    [ "$status" -eq 0 ]
    run bash -c "cd '$WORK' && copilot-launch-plan --no-resume --json | jq -r '.args | index(\"--experimental\") != null, index(\"--allow-all\") != null, (index(\"shell(git push --force)\") != null)'"
    [ "${lines[0]}" = "true" ]
    [ "${lines[1]}" = "true" ]
    [ "${lines[2]}" = "true" ]
}

@test "launch-plan --no-allow-all/--no-experimental/--no-default-deny-tools strip defaults" {
    run bash -c "cd '$WORK' && copilot-launch-plan --no-resume --no-allow-all --no-experimental --no-default-deny-tools --json | jq -r '.args | length'"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "launch-plan maps a prompt to autopilot" {
    run bash -c "cd '$WORK' && copilot-launch-plan --no-resume 'fix bug' --json | jq -r '.args | .[index(\"-p\")+1]'"
    [ "$status" -eq 0 ]
    [ "$output" = "fix bug" ]
}

@test "launch-plan treats update as passthrough" {
    run bash -c "cd '$WORK' && copilot-launch-plan update --json | jq -c '{passthrough, args}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"passthrough":true,"args":["update"]}' ]
}

@test "launch-plan auto-resumes a lone session for the directory" {
    make_session solo "Solo work" 2026-05-01T00:00:00Z main
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --json | jq -r '.args | .[index(\"--resume\")+1]'"
    [ "$status" -eq 0 ]
    [ "$output" = "solo" ]
}

@test "launch-plan --resume-latest picks the newest of several" {
    make_session old "Old" 2026-01-01T00:00:00Z main
    make_session new "New" 2026-02-01T00:00:00Z main
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --resume-latest --json | jq -r '.args | .[index(\"--resume\")+1]'"
    [ "$output" = "new" ]
}

@test "launch-plan resumes the only named session among unnamed stubs" {
    make_session stub1 "" 2026-03-01T00:00:00Z main
    make_session named "The Named One" 2026-02-01T00:00:00Z main
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --json | jq -r '.args | .[index(\"--resume\")+1]'"
    [ "$output" = "named" ]
}

@test "launch-plan --no-resume never adds --resume" {
    make_session solo "Solo" 2026-05-01T00:00:00Z main
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --no-resume --json | jq -r '.args | index(\"--resume\")'"
    [ "$output" = "null" ]
}

@test "launch-plan MCP autoConnect disables non-matching path-glob servers" {
    cat > "$COPILOT_HOME/mcp-config.json" <<EOF
{"mcpServers":{"always":{"autoConnect":true},"here":{"autoConnect":["$SESSION_CWD/*"]},"elsewhere":{"autoConnect":["/nope/*"]}}}
EOF
    mkdir -p "$SESSION_CWD/sub"
    run bash -c "cd '$SESSION_CWD/sub' && copilot-launch-plan --no-resume --json | jq -r '[.args as \$a | range(0;\$a|length) | select(\$a[.]==\"--disable-mcp-server\") | \$a[.+1]] | sort | join(\",\")'"
    [ "$status" -eq 0 ]
    [ "$output" = "elsewhere" ]
}

@test "launch-plan --enable-mcp-server forces a server on" {
    cat > "$COPILOT_HOME/mcp-config.json" <<EOF
{"mcpServers":{"elsewhere":{"autoConnect":["/nope/*"]}}}
EOF
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --no-resume --enable-mcp-server elsewhere --json | jq -r '[.args[] | select(.==\"elsewhere\")] | length'"
    [ "$output" = "0" ]
}

# ---- session CRUD --------------------------------------------------------

@test "copilot-session list filters to the current directory" {
    make_session here "Here" 2026-05-01T00:00:00Z main
    ( mkdir -p "$WORK/other" )
    run bash -c "cd '$SESSION_CWD' && copilot-session list --json | jq -r 'length'"
    [ "$output" = "1" ]
    run bash -c "cd '$WORK/other' && copilot-session list --json | jq -r 'length'"
    [ "$output" = "0" ]
}

@test "copilot-session list --all ignores the directory filter" {
    make_session here "Here" 2026-05-01T00:00:00Z main
    run bash -c "cd '$WORK' && copilot-session list --all --json | jq -r 'length'"
    [ "$output" = "1" ]
}

@test "copilot-session list preserves the branch of an unnamed session" {
    make_session stub1 "" 2026-03-01T00:00:00Z feature/x
    run bash -c "cd '$SESSION_CWD' && copilot-session list --json | jq -r '.[0].branch'"
    [ "$output" = "feature/x" ]
}

@test "copilot-session rename updates name and summary" {
    make_session ren "Old Name" 2026-05-01T00:00:00Z main
    echo "summary: Old Name" >> "$COPILOT_HOME/session-state/ren/workspace.yaml"
    run copilot-session rename ren "New Name"
    [ "$status" -eq 0 ]
    grep -q '^name: New Name$' "$COPILOT_HOME/session-state/ren/workspace.yaml"
    grep -q '^summary: New Name$' "$COPILOT_HOME/session-state/ren/workspace.yaml"
}

@test "copilot-session rename collapses a block-scalar name" {
    local d="$COPILOT_HOME/session-state/blk"
    mkdir -p "$d"
    printf 'id: blk\ncwd: %s\nupdated_at: 2026-05-01T00:00:00Z\nname: |-\n  Line one\n  Line two\nuser_named: false\n' "$SESSION_CWD" > "$d/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$d/events.jsonl"
    run copilot-session rename blk "Flat"
    [ "$status" -eq 0 ]
    grep -q '^name: Flat$' "$d/workspace.yaml"
    grep -q '^user_named: false$' "$d/workspace.yaml"
    ! grep -q 'Line one' "$d/workspace.yaml"
}

@test "copilot-session remove --dry-run keeps the session" {
    make_session rm1 "Removable" 2026-05-01T00:00:00Z main
    run copilot-session remove --dry-run rm1
    [ "$status" -eq 0 ]
    [ -d "$COPILOT_HOME/session-state/rm1" ]
}

@test "copilot-session remove deletes the session" {
    make_session rm1 "Removable" 2026-05-01T00:00:00Z main
    run copilot-session remove rm1
    [ "$status" -eq 0 ]
    [ ! -d "$COPILOT_HOME/session-state/rm1" ]
}

# ---- plugins / marketplaces / mcp ---------------------------------------

@test "copilot-plugin list parses plugins including unmarketed ones" {
    run bash -c "copilot-plugin list --json | jq -c '.[1] | {name, marketplace, version}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"name":"local-plugin","marketplace":null,"version":"0.1.0"}' ]
}

@test "copilot-plugin list glob filters by name" {
    run bash -c "copilot-plugin list 'dotnet*' --json | jq -r 'length'"
    [ "$output" = "1" ]
}

@test "copilot-marketplace list parses GitHub and URL sources" {
    run bash -c "copilot-marketplace list --json | jq -r '.[0].repository, .[1].repository'"
    [ "${lines[0]}" = "dotnet/skills" ]
    [ "${lines[1]}" = "https://example.com/mp.json" ]
}

@test "copilot-mcp list preserves url and source columns" {
    run bash -c "copilot-mcp list --json | jq -c '.[0] | {name, url, source, command}'"
    [ "$output" = '{"name":"ctx7","url":"https://mcp.context7.com/mcp","source":"user","command":null}' ]
}

@test "copilot-mcp list --source filters by source" {
    run bash -c "copilot-mcp list --source workspace --json | jq -r '.[0].name'"
    [ "$output" = "local" ]
}

@test "copilot-mcp add builds a stdio command line" {
    run copilot-mcp add myserver --command npx --arg -y --arg @my/mcp
    [ "$status" -eq 0 ]
    grep -q 'mcp add --transport stdio myserver -- npx -y @my/mcp' "$COPILOT_ARGS_LOG"
}

# ---- maintenance (node) --------------------------------------------------

@test "repair-events relocates orphaned tool events and strips errors" {
    local d="$COPILOT_HOME/session-state/rep"
    mkdir -p "$d"
    printf 'id: rep\ncwd: %s\nupdated_at: 2026-01-01T00:00:05Z\nname: Rep\n' "$SESSION_CWD" > "$d/workspace.yaml"
    cat > "$d/events.jsonl" <<'EOF'
{"type":"session.start","id":"s1","timestamp":"2026-01-01T00:00:00Z","data":{"sessionId":"rep"}}
{"type":"user.message","id":"u1","timestamp":"2026-01-01T00:00:01Z","data":{}}
{"type":"tool.execution_complete","id":"tc1","timestamp":"2026-01-01T00:00:02Z","data":{"toolCallId":"c1","model":"claude"}}
{"type":"assistant.message","id":"a1","timestamp":"2026-01-01T00:00:03Z","data":{"toolRequests":[{"toolCallId":"c1"}]}}
{"type":"session.error","id":"e1","timestamp":"2026-01-01T00:00:04Z","data":{}}
{"type":"assistant.turn_end","id":"te1","timestamp":"2026-01-01T00:00:05Z","data":{}}
EOF
    run copilot-session-maintenance repair-events rep --no-backup
    [ "$status" -eq 0 ]
    run bash -c "jq -r .type '$d/events.jsonl' | tr '\n' ','"
    [ "$output" = "session.start,user.message,assistant.message,tool.execution_complete,assistant.turn_end," ]
}

@test "compress keeps only the last N conversations" {
    local d="$COPILOT_HOME/session-state/cmp"
    mkdir -p "$d"
    printf 'id: cmp\ncwd: %s\nupdated_at: 2026-01-02T00:00:00Z\nname: Cmp\n' "$SESSION_CWD" > "$d/workspace.yaml"
    {
        echo '{"type":"session.start","id":"s","timestamp":"2026-01-01T00:00:00Z","data":{}}'
        for i in 1 2 3 4; do
            echo "{\"type\":\"user.message\",\"id\":\"u$i\",\"timestamp\":\"2026-01-01T00:0$i:00Z\",\"data\":{}}"
            echo "{\"type\":\"assistant.turn_end\",\"id\":\"a$i\",\"timestamp\":\"2026-01-01T00:0$i:30Z\",\"data\":{}}"
        done
    } > "$d/events.jsonl"
    run copilot-session-maintenance compress cmp --keep 2 --no-backup
    [ "$status" -eq 0 ]
    run bash -c "jq -r 'select(.type==\"user.message\").id' '$d/events.jsonl' | tr '\n' ','"
    [ "$output" = "u3,u4," ]
}

@test "merge combines sessions into one with a single session.start" {
    local a="$COPILOT_HOME/session-state/m1"
    local b="$COPILOT_HOME/session-state/m2"
    for pair in "m1:First:2026-01-01" "m2:Second:2026-02-01"; do
        id="${pair%%:*}"; rest="${pair#*:}"; nm="${rest%%:*}"; day="${rest##*:}"
        d="$COPILOT_HOME/session-state/$id"
        mkdir -p "$d/checkpoints"
        printf 'id: %s\ncwd: %s\nupdated_at: %sT00:00:00Z\nname: %s\n' "$id" "$SESSION_CWD" "$day" "$nm" > "$d/workspace.yaml"
        printf '{"type":"session.start","id":"s_%s","timestamp":"%sT00:00:00Z","data":{"sessionId":"%s"}}\n{"type":"user.message","id":"u_%s","timestamp":"%sT00:00:01Z","data":{}}\n{"type":"assistant.turn_end","id":"t_%s","timestamp":"%sT00:00:02Z","data":{}}\n' "$id" "$day" "$id" "$id" "$day" "$id" "$day" > "$d/events.jsonl"
    done
    run copilot-session-maintenance merge m1 m2
    [ "$status" -eq 0 ]
    new_id="${lines[-1]}"
    [ -d "$COPILOT_HOME/session-state/$new_id" ]
    run bash -c "jq -r 'select(.type==\"session.start\")' '$COPILOT_HOME/session-state/$new_id/events.jsonl' | jq -s 'length'"
    [ "$output" = "1" ]
    grep -q '^name: First + Second$' "$COPILOT_HOME/session-state/$new_id/workspace.yaml"
    # Sources preserved without --remove-source.
    [ -d "$COPILOT_HOME/session-state/m1" ]
}
