#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.native-scratch/mcp-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/bin" "$WORK/home"
    export COPILOT_HOME="$WORK/home" CALLS="$WORK/calls" RESPONSE="$WORK/response" NATIVE_STATUS=0
    printf '{"mcpServers":{}}\n' > "$RESPONSE"
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CALLS"
cat "$RESPONSE"
exit "$NATIVE_STATUS"
EOF
    chmod +x "$WORK/bin/copilot"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
}

teardown() { rm -rf -- "$WORK"; }

@test "MCP tools all none and restricted filters retain exact native argv and timeout bounds" {
    local transport tools timeout
    for transport in stdio http sse; do
        for tools in '*' '' 'read,write,tool.name:part-id'; do
            for timeout in 1 4294967295; do
                run copilot-mcp add synthetic --transport "$transport" --command example \
                    --arg 'two words' --url https://example.invalid/mcp --tools "$tools" --timeout "$timeout"
                [ "$status" -eq 0 ]
                if [[ -z "$tools" ]]; then grep -Fxq -- '--tools=' "$CALLS"
                else grep -Fxq -- "$tools" "$CALLS"; fi
                grep -Fxq -- "$timeout" "$CALLS"
                if [[ "$transport" == stdio ]]; then
                    grep -Fxq -- 'two words' "$CALLS"
                    ! grep -Fxq -- 'https://example.invalid/mcp' "$CALLS"
                else
                    grep -Fxq -- 'https://example.invalid/mcp' "$CALLS"
                    ! grep -Fxq -- 'example' "$CALLS"
                fi
            done
        done
    done
}

@test "MCP add rejects invalid tools bounds and missing values before even dry-run native calls" {
    local value
    for value in ',read' 'read,' 'read,,write' 'read, write' '*,read' '-read' 'read/tool'; do
        run copilot-mcp add synthetic --tools "$value" --dry-run
        [ "$status" -ne 0 ]
    done
    for value in 0 -1 4294967296 999999999999999999999 1.5 nope ''; do
        run copilot-mcp add synthetic --timeout "$value" --dry-run
        [ "$status" -ne 0 ]
    done
    run copilot-mcp add synthetic --tools
    [ "$status" -ne 0 ]
    run copilot-mcp add synthetic --timeout
    [ "$status" -ne 0 ]
    [ ! -e "$CALLS" ]
}

@test "MCP list reports boolean enabled and exact empty all restricted filters" {
    cat > "$RESPONSE" <<'EOF'
{"mcpServers":{"all":{"type":"http","url":"https://example.invalid/mcp","source":"user","enabled":true,"tools":"*"},
 "none":{"type":"stdio","command":"example","args":["two words","next"],"source":"workspace","enabled":false,"tools":""},
 "some":{"type":"sse","url":"https://example.invalid/sse","source":"plugin","enabled":true,"tools":"read,write"}}}
EOF
    run copilot-mcp list --json
    [ "$status" -eq 0 ]
    jq -e '.[0].enabled==true and .[0].tools=="*" and
        .[1].enabled==false and .[1].tools=="" and .[1].args=="two words next" and
        .[2].tools=="read,write"' <<< "$output"
    run copilot-mcp list none --source workspace
    [ "$status" -eq 0 ]
    [[ "$output" == *"enabled=false tools= "* ]]
}

@test "MCP list invalid output or failed valid partial output emits no inventory" {
    local fixture
    for fixture in '' '{}' '{"mcpServers":[]}' '{"mcpServers":{"bad":null}}' \
        '{"mcpServers":{"bad":{"type":"stdio","source":"user","enabled":"false","tools":"*"}}}' \
        '{"mcpServers":{"bad":{"type":"stdio","source":"user","enabled":true}}}' \
        '{"mcpServers":{"bad":{"type":"stdio","source":"user","enabled":true,"tools":[]}}}' \
        '{"mcpServers":{"bad":{"type":"stdio","source":"user","enabled":true,"tools":"*","args":[1]}}}' \
        '{"mcpServers":{"ok":{"type":"stdio","source":"user","enabled":true,"tools":"*"},"bad":{}}}' \
        '{"mcpServers":{}} {"mcpServers":{}}'; do
        printf '%s' "$fixture" > "$RESPONSE"
        run --separate-stderr copilot-mcp list --json
        [ "$status" -ne 0 ]
        [ -z "$output" ]
        [[ "$stderr" == *"invalid JSON or schema"* ]]
    done
    printf '{"mcpServers":{}}\n' > "$RESPONSE"
    export NATIVE_STATUS=17
    run --separate-stderr copilot-mcp list --json
    [ "$status" -eq 17 ]
    [ -z "$output" ]
    [[ "$stderr" == *"exit 17"* ]]
}

@test "MCP list successful empty map remains valid" {
    run copilot-mcp list --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
}

@test "MCP tools timeout keep symlink protection and preview-only behavior" {
    ln -s "$WORK/missing" "$COPILOT_HOME/mcp-config.json"
    run copilot-mcp add synthetic --tools= --timeout 1
    [ "$status" -ne 0 ]
    [ -L "$COPILOT_HOME/mcp-config.json" ]
    [ ! -e "$CALLS" ]
    run copilot-mcp add synthetic --tools= --timeout 1 --whatif
    [ "$status" -eq 0 ]
    [ -L "$COPILOT_HOME/mcp-config.json" ]
    [ ! -e "$CALLS" ]
}
