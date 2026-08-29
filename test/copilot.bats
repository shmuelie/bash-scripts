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

@test "launch-plan explicit --session-id suppresses automatic resume and picker" {
    make_session one "One" 2026-05-01T00:00:00Z main
    make_session two "Two" 2026-05-02T00:00:00Z main
    cat > "$STUB/fzf" <<'EOF'
#!/usr/bin/env bash
echo called >> "$FZF_LOG"
exit 1
EOF
    chmod +x "$STUB/fzf"
    export FZF_LOG="$WORK/fzf.log"

    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --session-id explicit-id --json |
        jq -c '{sessionId:(.args[.args|index(\"--session-id\")+1]),resume:(.args|index(\"--resume\"))}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"sessionId":"explicit-id","resume":null}' ]
    [ ! -e "$FZF_LOG" ]
}

@test "launch-plan explicit resume is honored alongside --session-id" {
    make_session one "One" 2026-05-01T00:00:00Z main
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --session-id explicit-id --resume-session one --json |
        jq -r '.args[.args|index(\"--resume\")+1]'"
    [ "$status" -eq 0 ]
    [ "$output" = "one" ]
}

@test "start-copilot --dry-run does not open automatic resume picker" {
    make_session one "One" 2026-05-01T00:00:00Z main
    make_session two "Two" 2026-05-02T00:00:00Z main
    cat > "$STUB/fzf" <<'EOF'
#!/usr/bin/env bash
echo called >> "$FZF_LOG"
exit 1
EOF
    chmod +x "$STUB/fzf"
    export FZF_LOG="$WORK/fzf.log"

    run bash -c "cd '$SESSION_CWD' && start-copilot --dry-run --passthru"
    [ "$status" -eq 0 ]
    [[ "$output" != *"--resume"* ]]
    [ ! -e "$FZF_LOG" ]
}

@test "start-copilot --dry-run still honors explicit resume" {
    make_session one "One" 2026-05-01T00:00:00Z main
    run bash -c "cd '$SESSION_CWD' && start-copilot --dry-run --passthru --resume-session one"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--resume one"* ]]
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
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --no-resume --enable-mcp-server elsewhere --json | jq -r '
        .args as \$a |
        [range(0;\$a|length) as \$i | select(\$a[\$i]==\"--enable-mcp-server\") | \$a[\$i+1]] as \$enabled |
        [range(0;\$a|length) as \$i | select(\$a[\$i]==\"--disable-mcp-server\") | \$a[\$i+1]] as \$disabled |
        [(\$enabled|index(\"elsewhere\")!=null),(\$disabled|index(\"elsewhere\")==null)] | @tsv'"
    [ "$output" = $'true\ttrue' ]
}

# ---- session CRUD --------------------------------------------------------

@test "copilot-session subcommand accepts --help and shows usage" {
    run copilot-session list --help
    [ "$status" -eq 0 ]
    [[ "$output" == Usage:* ]]
}

@test "copilot-session resume preserves -- passthrough (does not treat --help as usage)" {
    run copilot-session resume nosuch -- --help
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

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

@test "copilot-session list decodes quoted and block workspace scalars" {
    local d="$COPILOT_HOME/session-state/yaml"
    mkdir -p "$d"
    cat > "$d/workspace.yaml" <<EOF
id: yaml
cwd: '$SESSION_CWD'
updated_at: "2026-05-01T00:00:00Z"
branch: "feature/quote\\\\path:#hash"
repository: 'org/repo: # literal'
name: >-
  Name: # "quote"
  and backslash \\ path
unrelated: |
  keep: # this
  exactly
EOF
    printf '{"type":"session.start"}\n' > "$d/events.jsonl"
    run bash -c "cd '$SESSION_CWD' && copilot-session list --json |
        jq -c '.[0] | {name,branch,repository}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"name":"Name: # \"quote\" and backslash \\ path","branch":"feature/quote\\path:#hash","repository":"org/repo: # literal"}' ]
}

@test "copilot-session reads and replaces multiline quoted workspace scalars" {
    local d="$COPILOT_HOME/session-state/multiline"
    mkdir -p "$d"
    cat > "$d/workspace.yaml" <<EOF
id: multiline
cwd: "$SESSION_CWD"
updated_at: 2026-05-01T00:00:00Z
summary: "A long summary

  continued here"
unrelated: keep
EOF
    printf '{"type":"session.start"}\n' > "$d/events.jsonl"

    run bash -c "cd '$SESSION_CWD' && copilot-session list --json | jq -r '.[0].name'"
    [ "$status" -eq 0 ]
    [ "$output" = "A long summary continued here" ]

    run copilot-session rename multiline "New Summary"
    [ "$status" -eq 0 ]
    grep -q '^summary: "New Summary"$' "$d/workspace.yaml"
    grep -q '^unrelated: keep$' "$d/workspace.yaml"
    ! grep -q 'continued here' "$d/workspace.yaml"
}

@test "copilot-session rename updates name and summary" {
    make_session ren "Old Name" 2026-05-01T00:00:00Z main
    echo "summary: Old Name" >> "$COPILOT_HOME/session-state/ren/workspace.yaml"
    run copilot-session rename ren "New Name"
    [ "$status" -eq 0 ]
    run bash -c "copilot-session list --all --id ren --json | jq -r '.[0].name'"
    [ "$output" = "New Name" ]
    grep -q '^summary: "New Name"$' "$COPILOT_HOME/session-state/ren/workspace.yaml"
}

@test "copilot-session rename collapses a block-scalar name" {
    local d="$COPILOT_HOME/session-state/blk"
    mkdir -p "$d"
    printf 'id: blk\ncwd: %s\nupdated_at: 2026-05-01T00:00:00Z\nname: |-\n  Line one\n  Line two\nuser_named: false\n' "$SESSION_CWD" > "$d/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$d/events.jsonl"
    run copilot-session rename blk "Flat"
    [ "$status" -eq 0 ]
    grep -q '^name: "Flat"$' "$d/workspace.yaml"
    grep -q '^user_named: false$' "$d/workspace.yaml"
    ! grep -q 'Line one' "$d/workspace.yaml"
}

@test "copilot-session rename safely round-trips special characters" {
    local d="$COPILOT_HOME/session-state/special"
    mkdir -p "$d"
    cat > "$d/workspace.yaml" <<EOF
id: special
cwd: "$SESSION_CWD"
updated_at: 2026-05-01T00:00:00Z
name: Old
summary: Old
unrelated: |
  keep: # "quoted" \\ value
EOF
    printf '{"type":"session.start"}\n' > "$d/events.jsonl"
    local new_name='A: # "quote" \ path and it'\''s safe'
    run copilot-session rename special "$new_name"
    [ "$status" -eq 0 ]
    run bash -c "copilot-session list --all --id special --json | jq -r '.[0].name'"
    [ "$output" = "$new_name" ]
    grep -Fq '  keep: # "quoted" \ value' "$d/workspace.yaml"
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

@test "compress rejects invalid keep values without changing the session" {
    local d="$COPILOT_HOME/session-state/badkeep"
    mkdir -p "$d"
    printf 'id: badkeep\ncwd: %s\nupdated_at: 2026-01-02T00:00:00Z\nname: Bad\n' "$SESSION_CWD" > "$d/workspace.yaml"
    printf '{"type":"session.start","id":"s","data":{}}\n{"type":"user.message","id":"u","data":{}}\n' > "$d/events.jsonl"
    cp "$d/events.jsonl" "$d/original"
    local value
    for value in invalid -1 0; do
        run copilot-session-maintenance compress badkeep --keep "$value" --no-backup
        [ "$status" -ne 0 ]
        cmp -s "$d/original" "$d/events.jsonl"
        [ ! -e "$d/events.jsonl.bak" ]
    done
}

@test "Node compress defensively rejects invalid keep before writing" {
    local d="$COPILOT_HOME/session-state/nodekeep"
    mkdir -p "$d"
    printf '{"type":"session.start","id":"s","data":{}}\n' > "$d/events.jsonl"
    cp "$d/events.jsonl" "$d/original"
    run node "$REPO_ROOT/lib/copilot/session-maintenance.js" compress "$d" --keep nope --no-backup
    [ "$status" -ne 0 ]
    cmp -s "$d/original" "$d/events.jsonl"
}

@test "repair drops a malformed final line and backs up before writing" {
    local d="$COPILOT_HOME/session-state/malformed"
    mkdir -p "$d"
    printf 'id: malformed\ncwd: %s\nupdated_at: 2026-01-02T00:00:00Z\nname: Bad tail\n' "$SESSION_CWD" > "$d/workspace.yaml"
    printf '{"type":"session.start","id":"s","data":{}}\n{"type":"user.message","id":"u","data":{}}\n{"type":"assistant.message"' > "$d/events.jsonl"
    cp "$d/events.jsonl" "$d/original"
    run copilot-session-maintenance repair-events malformed
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped 1 malformed JSONL line."* ]]
    cmp -s "$d/original" "$d/events.jsonl.bak"
    run bash -c "jq -s 'length' '$d/events.jsonl'"
    [ "$output" = "2" ]
}

@test "compress repairs malformed input before compacting" {
    local d="$COPILOT_HOME/session-state/cmpbad"
    mkdir -p "$d"
    printf 'id: cmpbad\ncwd: %s\nupdated_at: 2026-01-02T00:00:00Z\nname: Cmp\n' "$SESSION_CWD" > "$d/workspace.yaml"
    {
        echo '{"type":"session.start","id":"s","data":{}}'
        for i in 1 2 3; do
            echo "{\"type\":\"user.message\",\"id\":\"u$i\",\"data\":{}}"
            echo "{\"type\":\"assistant.turn_end\",\"id\":\"a$i\",\"data\":{}}"
        done
        printf '{"type":"assistant.message"'
    } > "$d/events.jsonl"
    run copilot-session-maintenance compress cmpbad --keep 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped 1 malformed JSONL line."* ]]
    grep -q '{"type":"assistant.message"$' "$d/events.jsonl.bak"
    run bash -c "jq -r 'select(.type==\"user.message\").id' '$d/events.jsonl' | tr '\n' ','"
    [ "$output" = "u2,u3," ]
}

@test "compress refuses an entirely invalid stream without writing" {
    local d="$COPILOT_HOME/session-state/allbad"
    mkdir -p "$d"
    printf 'id: allbad\ncwd: %s\nupdated_at: 2026-01-02T00:00:00Z\nname: Bad\n' "$SESSION_CWD" > "$d/workspace.yaml"
    printf '{"broken"\n' > "$d/events.jsonl"
    cp "$d/events.jsonl" "$d/original"
    run copilot-session-maintenance compress allbad --keep 1 --no-backup
    [ "$status" -ne 0 ]
    [[ "$output" != *"$REPO_ROOT/lib/copilot/session-maintenance.js:"* ]]
    cmp -s "$d/original" "$d/events.jsonl"
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
    printf '{"type":"truncated"' >> "$b/events.jsonl"
    run copilot-session-maintenance merge m1 m2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped 1 malformed JSONL line."* ]]
    new_id="${lines[-1]}"
    [ -d "$COPILOT_HOME/session-state/$new_id" ]
    run bash -c "jq -r 'select(.type==\"session.start\")' '$COPILOT_HOME/session-state/$new_id/events.jsonl' | jq -s 'length'"
    [ "$output" = "1" ]
    run bash -c "copilot-session list --all --id '$new_id' --json | jq -r '.[0].name'"
    [ "$output" = "First + Second" ]
    grep -q "^id: $new_id$" "$COPILOT_HOME/session-state/$new_id/workspace.yaml"
    grep -q '^updated_at: [^"]' "$COPILOT_HOME/session-state/$new_id/workspace.yaml"
    # Sources preserved without --remove-source.
    [ -d "$COPILOT_HOME/session-state/m1" ]
}

@test "merge safely encodes special YAML names and preserves unrelated fields" {
    local id d
    for id in ya yb; do
        d="$COPILOT_HOME/session-state/$id"
        mkdir -p "$d"
        if [[ "$id" == ya ]]; then
            cat > "$d/workspace.yaml" <<EOF
id: ya
cwd: "$SESSION_CWD"
updated_at: 2026-01-01T00:00:00Z
name: 'First: # value'
unrelated: |
  keep: "this" \\ field
EOF
        else
            cat > "$d/workspace.yaml" <<EOF
id: yb
cwd: "$SESSION_CWD"
updated_at: 2026-02-01T00:00:00Z
name: >-
  Second "quoted"
  \\ path
unrelated: |
  keep: "this" \\ field
EOF
        fi
        printf '{"type":"session.start","id":"s_%s","timestamp":"2026-01-01T00:00:00Z","data":{"sessionId":"%s"}}\n' "$id" "$id" > "$d/events.jsonl"
    done
    run copilot-session-maintenance merge ya yb
    [ "$status" -eq 0 ]
    local new_id="${lines[-1]}"
    run bash -c "copilot-session list --all --id '$new_id' --json | jq -r '.[0].name'"
    [ "$output" = 'First: # value + Second "quoted" \ path' ]
    grep -Fq '  keep: "this" \ field' "$COPILOT_HOME/session-state/$new_id/workspace.yaml"
}

@test "merge with an invalid source does not remove source sessions" {
    local id d
    for id in good bad; do
        d="$COPILOT_HOME/session-state/$id"
        mkdir -p "$d"
        printf 'id: %s\ncwd: %s\nupdated_at: 2026-01-01T00:00:00Z\nname: %s\n' "$id" "$SESSION_CWD" "$id" > "$d/workspace.yaml"
    done
    printf '{"type":"session.start","id":"s","data":{"sessionId":"good"}}\n' > "$COPILOT_HOME/session-state/good/events.jsonl"
    printf '{"broken"\n' > "$COPILOT_HOME/session-state/bad/events.jsonl"
    run copilot-session-maintenance merge good bad --remove-source
    [ "$status" -ne 0 ]
    [ -d "$COPILOT_HOME/session-state/good" ]
    [ -d "$COPILOT_HOME/session-state/bad" ]
}
