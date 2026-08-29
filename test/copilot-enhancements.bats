#!/usr/bin/env bats
# Coverage for Copilot session selection, launch mappings, and path hardening.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-work/copilot-enhancements-${BATS_TEST_NUMBER}-$$"
    rm -rf -- "$WORK"
    mkdir -p "$WORK/.copilot/session-state" "$WORK/stub" "$WORK/project"
    export WORK
    export COPILOT_HOME="$WORK/.copilot"
    export SESSION_CWD="$WORK/project"
    export COPILOT_RECORD="$WORK/copilot-record"

    cat > "$WORK/stub/copilot" <<'EOF'
#!/usr/bin/env bash
{
    printf 'cwd=%s\n' "$PWD"
    for arg in "$@"; do printf 'arg=%s\n' "$arg"; done
} > "$COPILOT_RECORD"
EOF
    chmod +x "$WORK/stub/copilot"
    export PATH="$WORK/stub:$REPO_ROOT/bin:$PATH"
}

teardown() {
    rm -rf -- "$WORK"
    rmdir "$REPO_ROOT/.test-work" 2>/dev/null || true
}

make_session() {
    local id="$1" name="$2" updated="$3" branch="$4"
    local repository="${5:-owner/repo}" cwd="${6:-$SESSION_CWD}"
    local event_count="${7:-1}" d i
    d="$COPILOT_HOME/session-state/$id"
    mkdir -p "$d"
    {
        printf 'id: %s\n' "$id"
        printf 'cwd: %s\n' "$cwd"
        printf 'updated_at: %s\n' "$updated"
        printf 'branch: %s\n' "$branch"
        printf 'repository: %s\n' "$repository"
        printf 'name: %s\n' "$name"
    } > "$d/workspace.yaml"
    : > "$d/events.jsonl"
    for ((i = 0; i < event_count; i++)); do
        printf '{"type":"session.start","id":"event-%s"}\n' "$i" >> "$d/events.jsonl"
    done
}

make_merge_session() {
    local id="$1" updated="$2" d
    d="$COPILOT_HOME/session-state/$id"
    mkdir -p "$d"
    printf 'id: %s\ncwd: %s\nupdated_at: %s\nname: %s\n' \
        "$id" "$SESSION_CWD" "$updated" "$id" > "$d/workspace.yaml"
    printf '{"type":"session.start","id":"s-%s","timestamp":"%s","data":{"sessionId":"%s"}}\n' \
        "$id" "$updated" "$id" > "$d/events.jsonl"
}

@test "launch plan maps approval, tool, usage, and every MCP enable flag" {
    cat > "$COPILOT_HOME/mcp-config.json" <<EOF
{"mcpServers":{"one":{"autoConnect":["$WORK/elsewhere/*"]},"two":{"autoConnect":["$WORK/elsewhere/*"]}}}
EOF
    run bash -c "cd '$SESSION_CWD' && copilot-launch-plan --no-resume --assisted-approval \
        --allow-all-tools --usage-output-file '$WORK/usage.json' \
        --enable-mcp-server one --enable-mcp-server two --json | jq -c '
        .args as \$a |
        {allowAll:(\$a|index(\"--allow-all\")),
         allowTools:(\$a|index(\"--allow-all-tools\")!=null),
         assisted:(\$a|index(\"--assisted-approval\")!=null),
         usage:\$a[(\$a|index(\"--usage-output-file\"))+1],
         enabled:[range(0;\$a|length) as \$i |
             select(\$a[\$i]==\"--enable-mcp-server\") | \$a[\$i+1]],
         disabled:[range(0;\$a|length) as \$i |
             select(\$a[\$i]==\"--disable-mcp-server\") | \$a[\$i+1]]}'"
    [ "$status" -eq 0 ]
    [ "$output" = "{\"allowAll\":null,\"allowTools\":true,\"assisted\":true,\"usage\":\"$WORK/usage.json\",\"enabled\":[\"one\",\"two\"],\"disabled\":[]}" ]
}

@test "assisted approval warns without experimental mode" {
    run copilot-launch-plan --no-resume --no-experimental --assisted-approval --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning:"* ]]
    [[ "$output" == *"--assisted-approval"* ]]
}

@test "launch plan value options fail clearly when values are missing" {
    local option
    for option in --disable-mcp-server --name --session-id --model --change-dir; do
        run copilot-launch-plan --no-resume "$option"
        [ "$status" -ne 0 ]
        [[ "$output" == *"requires a value"* || "$output" == *"requires a server name"* ]]
        [[ "$output" != *"unbound variable"* ]]
    done
}

@test "launch wrappers preserve adjacent values and post-double-dash flags" {
    run copilot-launch-plan --no-resume --usage-output-file --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"--usage-output-file --json"* ]]
    [[ "$output" != \{* ]]

    run start-copilot --passthru --no-resume --no-default-deny-tools \
        --usage-output-file "$WORK/usage.json" --enable-mcp-server local \
        --allow-all-tools -- --passthru --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"--usage-output-file $WORK/usage.json"* ]]
    [[ "$output" == *"--enable-mcp-server local"* ]]
    [[ "$output" == *"--allow-all-tools"* ]]
    [[ "$output" != *" --allow-all "* ]]
    [[ "$output" == *"--passthru --dry-run"* ]]
}

@test "global selector filters, picks the newest first match, and resumes recorded cwd" {
    mkdir -p "$WORK/other"
    make_session old "Old work" 2026-01-01T00:00:00Z feature/old owner/other "$WORK/other" 2
    make_session new "New work" 2026-02-01T00:00:00Z Feature/New Owner/Repo "$SESSION_CWD" 3

    run bash -c "cd '$WORK' && copilot-session select --repository 'owner/re*' \
        --branch 'feature/*' --first 1 'continue work' -- --model fast"
    [ "$status" -eq 0 ]
    grep -Fxq "cwd=$SESSION_CWD" "$COPILOT_RECORD"
    grep -Fxq 'arg=--resume' "$COPILOT_RECORD"
    grep -Fxq 'arg=new' "$COPILOT_RECORD"
    grep -Fxq 'arg=continue work' "$COPILOT_RECORD"
    grep -Fxq 'arg=--model' "$COPILOT_RECORD"
    grep -Fxq 'arg=fast' "$COPILOT_RECORD"
}

@test "global selector picker displays session details and honors stay-in-directory" {
    make_session older "Older" 2026-01-01T00:00:00Z dev owner/old "$SESSION_CWD" 1
    make_session newer "Newer" 2026-02-01T00:00:00Z main owner/new "$SESSION_CWD" 4
    export PICKER_LOG="$WORK/picker"
    cat > "$WORK/stub/fzf" <<'EOF'
#!/usr/bin/env bash
cat > "$PICKER_LOG"
sed -n '2p' "$PICKER_LOG"
EOF
    chmod +x "$WORK/stub/fzf"

    run bash -c "cd '$WORK' && copilot-session select --stay-in-directory"
    [ "$status" -eq 0 ]
    grep -Fq 'Newer | owner/new | main' "$PICKER_LOG"
    grep -Fq "$SESSION_CWD | 2026-02-01T00:00:00Z | events: 4" "$PICKER_LOG"
    grep -Fxq "cwd=$WORK" "$COPILOT_RECORD"
    grep -Fxq 'arg=older' "$COPILOT_RECORD"
}

@test "global selector dry-run resolves exactly one session without a picker" {
    make_session one "One" 2026-01-01T00:00:00Z main
    make_session two "Two" 2026-02-01T00:00:00Z main
    cat > "$WORK/stub/fzf" <<'EOF'
#!/usr/bin/env bash
echo called > "$WORK/fzf-called"
exit 1
EOF
    chmod +x "$WORK/stub/fzf"

    run copilot-session select --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Multiple Copilot sessions matched"* ]]
    [ ! -e "$WORK/fzf-called" ]

    run copilot-session select --dry-run --first 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"What if: Resume Copilot session two from $SESSION_CWD"* ]]
    [ ! -e "$COPILOT_RECORD" ]
}

@test "global selector reports no matches and missing recorded cwd" {
    make_session missing "Missing" 2026-01-01T00:00:00Z main owner/repo "$WORK/gone"
    run copilot-session select --id nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"No Copilot sessions matched"* ]]

    run copilot-session select --id missing
    [ "$status" -ne 0 ]
    [[ "$output" == *"Recorded working directory"* ]]
    [[ "$output" == *"$WORK/gone"* ]]
}

@test "session commands reject path-like IDs and symlink escapes" {
    local outside="$WORK/outside"
    mkdir -p "$outside"
    printf 'keep\n' > "$outside/sentinel"

    local bad
    for bad in . .. ../outside sub/session 'C:\outside' 'stream:name' /outside; do
        run copilot-session remove "$bad"
        [ "$status" -ne 0 ]
        [ -f "$outside/sentinel" ]
    done

    run copilot-session list --all --id ../outside --json
    [ "$status" -ne 0 ]

    ln -s "$outside" "$COPILOT_HOME/session-state/escape"
    run copilot-session rename escape changed
    [ "$status" -ne 0 ]
    [[ "$output" == *"canonical direct child"* ]]
    [ -f "$outside/sentinel" ]

    run copilot-session-maintenance repair-events escape --no-backup
    [ "$status" -ne 0 ]
    [ -f "$outside/sentinel" ]
}

@test "crafted workspace IDs cannot redirect destructive operations" {
    local safe="$COPILOT_HOME/session-state/safe" outside="$WORK/outside"
    mkdir -p "$safe" "$outside"
    printf 'keep\n' > "$outside/sentinel"
    printf 'id: ../outside\ncwd: %s\nupdated_at: 2026-01-01T00:00:00Z\nname: Safe\n' \
        "$SESSION_CWD" > "$safe/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$safe/events.jsonl"

    run copilot-session remove safe
    [ "$status" -eq 0 ]
    [ ! -e "$safe" ]
    [ -f "$outside/sentinel" ]
}

@test "merge re-resolves source IDs before invoking Node" {
    make_merge_session first 2026-01-01T00:00:00Z
    make_merge_session second 2026-02-01T00:00:00Z
    mkdir -p "$WORK/outside"
    printf 'keep\n' > "$WORK/outside/sentinel"
    cat > "$WORK/stub/cat" <<'EOF'
#!/usr/bin/env bash
mv "$COPILOT_HOME/session-state/first" "$COPILOT_HOME/session-state/first-original"
ln -s "$WORK/outside" "$COPILOT_HOME/session-state/first"
printf '11111111-1111-4111-8111-111111111111\n'
EOF
    chmod +x "$WORK/stub/cat"

    run copilot-session-maintenance merge first second
    [ "$status" -ne 0 ]
    [[ "$output" == *"canonical direct child"* ]]
    [ -f "$WORK/outside/sentinel" ]
    [ -d "$COPILOT_HOME/session-state/first-original" ]
    [ -d "$COPILOT_HOME/session-state/second" ]
    [ ! -e "$COPILOT_HOME/session-state/11111111-1111-4111-8111-111111111111" ]
}

@test "failed merge removes a partial destination and preserves every source" {
    make_merge_session first 2026-01-01T00:00:00Z
    make_merge_session second 2026-02-01T00:00:00Z
    mkdir -p "$COPILOT_HOME/session-state/second/files"
    ln -s "$WORK/does-not-exist" "$COPILOT_HOME/session-state/second/files/broken"

    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [[ "$output" == *"Merge failed"* ]]
    [ -d "$COPILOT_HOME/session-state/first" ]
    [ -d "$COPILOT_HOME/session-state/second" ]
    run bash -c "find '$COPILOT_HOME/session-state' -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '"
    [ "$output" = "2" ]
}

@test "merge JSON failures preserve sources without leaving a destination" {
    make_merge_session first 2026-01-01T00:00:00Z
    make_merge_session second 2026-02-01T00:00:00Z
    mkdir -p "$COPILOT_HOME/session-state/second/rewind-snapshots"
    printf '{"snapshots":[' > "$COPILOT_HOME/session-state/second/rewind-snapshots/index.json"

    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unexpected end of JSON input"* ]]
    [[ "$output" == *"Merge failed"* ]]
    [ -d "$COPILOT_HOME/session-state/first" ]
    [ -d "$COPILOT_HOME/session-state/second" ]
    run bash -c "find '$COPILOT_HOME/session-state' -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '"
    [ "$output" = "2" ]
}

@test "merge final metadata repair failures clean the partial destination" {
    make_merge_session first 2026-01-01T00:00:00Z
    make_merge_session second 2026-02-01T00:00:00Z
    cat > "$WORK/stub/mktemp" <<'EOF'
#!/usr/bin/env bash
printf 'forced final metadata repair failure\n' >&2
exit 1
EOF
    chmod +x "$WORK/stub/mktemp"

    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [[ "$output" == *"forced final metadata repair failure"* ]]
    [[ "$output" == *"Merge failed"* ]]
    [ -d "$COPILOT_HOME/session-state/first" ]
    [ -d "$COPILOT_HOME/session-state/second" ]
    run bash -c "find '$COPILOT_HOME/session-state' -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '"
    [ "$output" = "2" ]
}
