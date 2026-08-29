#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-work-dev-setup-${BATS_TEST_NUMBER:-0}-$$"
    rm -rf "$WORK"
    mkdir -p "$WORK/stub"
    STUB="$WORK/stub"
    STATE="$WORK/state"
    CALL_LOG="$WORK/calls.log"
    : > "$STATE"
    : > "$CALL_LOG"
    export SHM_SETUP_BIN_DIR="$STUB"
    export STATE CALL_LOG

    cat > "$STUB/copilot-plugin" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "list" ]]; then
    awk -F: '$1=="plugin" {printf "{\"name\":\"%s\",\"fullName\":\"%s\",\"marketplace\":null,\"version\":\"1\"}\n",$2,$2}' "$STATE" |
        jq -s .
elif [[ "$1" == "install" ]]; then
    printf 'plugin:%s\n' "${2##*/}" >> "$STATE"
    printf 'plugin install %s\n' "$2" >> "$CALL_LOG"
fi
EOF
    cat > "$STUB/copilot-marketplace" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "list" ]]; then
    awk -F: '$1=="market" {printf "{\"name\":\"%s\",\"repository\":\"%s\"}\n",$2,$3}' "$STATE" |
        jq -s .
elif [[ "$1" == "add" ]]; then
    printf 'market:demo:%s\n' "$2" >> "$STATE"
    printf 'market add %s\n' "$2" >> "$CALL_LOG"
fi
EOF
    cat > "$STUB/uv-tool" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "list" ]]; then
    name="$2"
    awk -F: -v name="$name" '$1=="uv" && $2==name {printf "{\"name\":\"%s\",\"version\":\"1\"}\n",$2}' "$STATE" |
        jq -s .
elif [[ "$1" == "install" ]]; then
    printf 'uv:%s\n' "$2" >> "$STATE"
    printf 'uv install %s\n' "$2" >> "$CALL_LOG"
fi
EOF
    chmod +x "$STUB"/*
}

teardown() {
    rm -rf "$WORK"
}

write_config() {
    cat > "$WORK/setup.json"
}

@test "dev-setup applies resources then becomes idempotent" {
    write_config <<EOF
{"version":1,"resources":[
  {"type":"symlink","path":"$WORK/link","target":"$WORK/target"},
  {"type":"copilotPlugin","source":"owner/demo-plugin"},
  {"type":"copilotMarketplace","name":"demo","repository":"owner/market"},
  {"type":"uvTool","name":"ruff"}
]}
EOF

    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --json
    [ "$status" -eq 0 ]
    [ "$(jq '[.[] | select(.status=="changed")] | length' <<< "$output")" -eq 4 ]
    [ "$(readlink "$WORK/link")" = "$WORK/target" ]

    : > "$CALL_LOG"
    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --json
    [ "$status" -eq 0 ]
    [ "$(jq '[.[] | select(.status=="satisfied")] | length' <<< "$output")" -eq 4 ]
    [ ! -s "$CALL_LOG" ]
}

@test "check is nonzero for unsatisfied resources and uses whole names" {
    printf 'plugin:demo-plugin-extra\n' >> "$STATE"
    write_config <<'EOF'
{"version":1,"resources":[{"type":"copilotPlugin","source":"owner/demo-plugin"}]}
EOF

    run "$REPO_ROOT/bin/dev-setup" check "$WORK/setup.json" --json
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' <<< "$output")" = "unsatisfied" ]
}

@test "dry-run reports changes without modifying resources" {
    write_config <<EOF
{"version":1,"resources":[{"type":"symlink","path":"$WORK/link","target":"$WORK/target"}]}
EOF

    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --dry-run --json
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/link" ]
    [ "$(jq -r '.[0].status' <<< "$output")" = "wouldChange" ]
}

@test "invalid config and URL plugin without a name are rejected" {
    write_config <<'EOF'
{"version":1,"resources":[{"type":"copilotPlugin","source":"https://example.com/plugin.zip"}]}
EOF
    run "$REPO_ROOT/bin/dev-setup" check "$WORK/setup.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid setup config"* ]]

    printf '{"version":2,"resources":[]}\n' > "$WORK/setup.json"
    run "$REPO_ROOT/bin/dev-setup" check "$WORK/setup.json"
    [ "$status" -ne 0 ]

    write_config <<'EOF'
{"version":1,"resources":[{"type":"copilotPlugin","source":"file:///plugins/plugin.zip"}]}
EOF
    run "$REPO_ROOT/bin/dev-setup" check "$WORK/setup.json"
    [ "$status" -ne 0 ]
}

@test "symlink replacement requires force and never replaces a directory" {
    printf 'file\n' > "$WORK/link"
    write_config <<EOF
{"version":1,"resources":[{"type":"symlink","path":"$WORK/link","target":"$WORK/target"}]}
EOF
    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --json
    [ "$status" -ne 0 ]
    [ -f "$WORK/link" ]

    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --force --json
    [ "$status" -eq 0 ]
    [ -L "$WORK/link" ]

    rm "$WORK/link"
    mkdir "$WORK/link"
    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --force --json
    [ "$status" -ne 0 ]
    [ -d "$WORK/link" ]
}

@test "apply continues after a resource failure" {
    cat > "$STUB/copilot-plugin" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "list" ]] && { printf '[]\n'; exit 0; }
printf 'plugin failure\n' >&2
exit 9
EOF
    chmod +x "$STUB/copilot-plugin"
    write_config <<'EOF'
{"version":1,"resources":[
  {"type":"copilotPlugin","source":"owner/broken"},
  {"type":"uvTool","name":"ruff"}
]}
EOF

    run "$REPO_ROOT/bin/dev-setup" apply "$WORK/setup.json" --json
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' <<< "$output")" = "failed" ]
    [ "$(jq -r '.[1].status' <<< "$output")" = "changed" ]
    grep -q '^uv install ruff$' "$CALL_LOG"
}

@test "uv-tool lists exact names and installs only when absent" {
    cat > "$STUB/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "tool list" ]]; then
    printf 'ruff-extra v2.0.0\nruff v1.0.0\n- ruff\nvulture v2.14\n- vulture\n'
elif [[ "$1 $2" == "tool install" ]]; then
    printf 'real uv install %s\n' "$3" >> "$CALL_LOG"
fi
EOF
    chmod +x "$STUB/uv"
    export PATH="$STUB:$REPO_ROOT/bin:$PATH"

    run "$REPO_ROOT/bin/uv-tool" list ruff --json
    [ "$status" -eq 0 ]
    [ "$(jq -r 'length' <<< "$output")" -eq 1 ]
    [ "$(jq -r '.[0].name' <<< "$output")" = "ruff" ]
    run "$REPO_ROOT/bin/uv-tool" list --json
    [ "$(jq '[.[] | select(.name=="-")] | length' <<< "$output")" -eq 0 ]

    run "$REPO_ROOT/bin/uv-tool" install ruff
    [ "$status" -eq 0 ]
    [ ! -s "$CALL_LOG" ]

    run "$REPO_ROOT/bin/uv-tool" install black
    [ "$status" -eq 0 ]
    grep -q '^real uv install black$' "$CALL_LOG"
}
