#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export COPILOT_HOME="$WORK/home" CALLS="$WORK/calls"
    mkdir -p "$COPILOT_HOME" "$WORK/bin"
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
printf '{"mcpServers":{}}\n' > "$COPILOT_HOME/new-config"
mv "$COPILOT_HOME/new-config" "$COPILOT_HOME/mcp-config.json"
EOF
    chmod +x "$WORK/bin/copilot"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
}

teardown() {
    rm -rf -- "$WORK"
}

@test "MCP add and remove reject existing and dangling managed links before native mutation" {
    local target cmd
    printf '{"managed":true}\n' > "$WORK/target"
    for target in "$WORK/target" "$WORK/dangling"; do
        ln -s "$target" "$COPILOT_HOME/mcp-config.json"
        for cmd in add remove; do
            run copilot-mcp "$cmd" server
            [ "$status" -ne 0 ]
            [[ "$output" == *"Manage its target directly"* ]]
            [ -L "$COPILOT_HOME/mcp-config.json" ]
            [ "$(readlink "$COPILOT_HOME/mcp-config.json")" = "$target" ]
            [ ! -e "$CALLS" ]
        done
        unlink "$COPILOT_HOME/mcp-config.json"
    done
    [ "$(cat "$WORK/target")" = '{"managed":true}' ]
    [ ! -e "$WORK/dangling" ]
}

@test "MCP previews never mutate linked config and remove accepts either flag position" {
    ln -s "$WORK/dangling" "$COPILOT_HOME/mcp-config.json"
    local flag
    for flag in --dry-run --whatif; do
        run copilot-mcp add server --command example "$flag"
        [ "$status" -eq 0 ]
        [[ "$output" == *"What if:"* ]]
        run copilot-mcp remove server "$flag"
        [ "$status" -eq 0 ]
        [[ "$output" == *"What if:"* ]]
        run copilot-mcp remove "$flag" server
        [ "$status" -eq 0 ]
        [[ "$output" == *"What if:"* ]]
    done
    [ -L "$COPILOT_HOME/mcp-config.json" ]
    [ ! -e "$WORK/dangling" ]
    [ ! -e "$CALLS" ]
}

@test "MCP add and remove retain native behavior for missing and ordinary config" {
    run copilot-mcp add server --command example --arg one
    [ "$status" -eq 0 ]
    grep -Fxq 'mcp add --transport stdio server -- example one' "$CALLS"
    [ -f "$COPILOT_HOME/mcp-config.json" ]
    run copilot-mcp remove server
    [ "$status" -eq 0 ]
    grep -Fxq 'mcp remove server' "$CALLS"
}

@test "MCP remove rejects extra arguments and unknown flags before native mutation" {
    run copilot-mcp remove server --unknown
    [ "$status" -ne 0 ]
    run copilot-mcp remove server another
    [ "$status" -ne 0 ]
    run copilot-mcp remove --dry-run
    [ "$status" -ne 0 ]
    [ ! -e "$CALLS" ]
}
