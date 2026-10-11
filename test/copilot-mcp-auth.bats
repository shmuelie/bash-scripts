#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.native-scratch/auth-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/bin" "$WORK/home"
    export COPILOT_HOME="$WORK/home" CALLS="$WORK/calls"
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$CALLS"
EOF
    cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected authentication/network invocation\n' >> "$CALLS"
exit 99
EOF
    cp "$WORK/bin/gh" "$WORK/bin/curl"
    chmod +x "$WORK/bin/"*
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    CONFIG='{"mcpServers":{"one":{"type":"http","url":"https://one.example.invalid/mcp"},"two":{"type":"sse","url":"https://two.example.invalid:8443/events"}}}'
}

teardown() { rm -rf -- "$WORK"; }

@test "multiple independent MCP auth scopes retain exact config and flags without authenticating" {
    run copilot-launch-plan --no-resume --additional-mcp-config "$CONFIG" \
        --mcp-github-auth one=https://one.example.invalid \
        --mcp-github-auth two=https://two.example.invalid:8443 --json
    [ "$status" -eq 0 ]
    jq -e --arg cfg "$CONFIG" '.args as $a |
        [$a[] | select(startswith("one=") or startswith("two="))] ==
            ["one=https://one.example.invalid","two=https://two.example.invalid:8443"] and
        ($a | index($cfg)) != null' <<< "$output"
    [ ! -e "$CALLS" ]
}

@test "MCP auth config files and literal loopback HTTP support independent approved origins" {
    printf '{"mcpServers":{"local":{"type":"http","url":"http://127.0.0.1:8080/mcp"}}}\n' > "$COPILOT_HOME/local.json"
    printf '{"mcpServers":{"ipv6":{"url":"http://[::1]/mcp"}}}\n' > "$WORK/ipv6.json"
    run copilot-launch-plan --no-resume --additional-mcp-config '@~/local.json' \
        --additional-mcp-config "@$WORK/ipv6.json" --mcp-github-auth local=http://127.0.0.1:8080 \
        --mcp-github-auth ipv6=http://[::1]:80/ --json
    [ "$status" -eq 0 ]
    [ ! -e "$CALLS" ]
}

@test "MCP auth malformed scopes reject secrets paths queries nonliteral HTTP and duplicate scopes" {
    local scope
    for scope in 'one=synthetic-credential' 'one=https://user:synthetic-password@one.example.invalid' \
        'one=https://one.example.invalid/path' 'one=https://one.example.invalid?query' \
        'one=https://one.example.invalid#fragment' 'one=http://one.example.invalid' \
        'one=http://localhost' 'one=http://127.1' 'one=http://127.0.0.2' \
        'one=https://one.example.invalid:99999' '=https://one.example.invalid' \
        $'one=https://one.example.invalid\n'; do
        run start-copilot --no-resume --additional-mcp-config "$CONFIG" --mcp-github-auth "$scope"
        [ "$status" -ne 0 ]
        [[ "$output" != *"synthetic-credential"* ]]
        [[ "$output" != *"synthetic-password"* ]]
    done
    run start-copilot --no-resume --additional-mcp-config "$CONFIG" \
        --mcp-github-auth one=https://one.example.invalid --mcp-github-auth one=https://one.example.invalid
    [ "$status" -ne 0 ]
    [ ! -e "$CALLS" ]
}

@test "MCP auth requires explicit matching remote server scheme host port and no URL credentials" {
    local config
    for config in '{"mcpServers":{"one":{"type":"stdio","url":"https://one.example.invalid/mcp"}}}' \
        '{"mcpServers":{"one":{"type":"http","url":"https://other.example.invalid/mcp"}}}' \
        '{"mcpServers":{"one":{"url":"http://one.example.invalid/mcp"}}}' \
        '{"mcpServers":{"one":{"url":"https://one.example.invalid:8443/mcp"}}}' \
        '{"mcpServers":{"one":{"url":"https://user:synthetic-password@one.example.invalid/mcp"}}}' \
        '{"mcpServers":{"two":{"url":"https://one.example.invalid/mcp"}}}' \
        '{"mcpServers":{"one":null}}' '{"mcpServers":[]}' '{}'; do
        run start-copilot --no-resume --additional-mcp-config "$config" \
            --mcp-github-auth one=https://one.example.invalid
        [ "$status" -ne 0 ]
        [[ "$output" != *"synthetic-password"* ]]
    done
    printf '%s\n' "$CONFIG" > "$COPILOT_HOME/mcp-config.json"
    run start-copilot --no-resume --mcp-github-auth one=https://one.example.invalid
    [ "$status" -ne 0 ]
    [ ! -e "$CALLS" ]
}

@test "MCP auth rejects invalid files duplicate explicit names and missing values before launch" {
    run start-copilot --no-resume --additional-mcp-config "@$WORK/missing" \
        --mcp-github-auth one=https://one.example.invalid
    [ "$status" -ne 0 ]
    run start-copilot --no-resume --additional-mcp-config "$CONFIG" --additional-mcp-config "$CONFIG" \
        --mcp-github-auth one=https://one.example.invalid
    [ "$status" -ne 0 ]
    run start-copilot --no-resume --mcp-github-auth
    [ "$status" -ne 0 ]
    run start-copilot --no-resume --additional-mcp-config
    [ "$status" -ne 0 ]
    [ ! -e "$CALLS" ]
}

@test "MCP auth previews redact inline config and never authenticate or launch" {
    local config='{"mcpServers":{"one":{"type":"http","url":"https://one.example.invalid/mcp","headers":{"X-Synthetic":"private-fixture"}}}}'
    run start-copilot --no-resume --additional-mcp-config "$config" \
        --mcp-github-auth one=https://one.example.invalid --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"private-fixture"* ]]
    [[ "$output" == *"redacted"* ]]
    run start-copilot --no-resume --additional-mcp-config "$config" \
        --mcp-github-auth one=https://one.example.invalid --passthru
    [ "$status" -eq 0 ]
    [[ "$output" != *"private-fixture"* ]]
    [ ! -e "$CALLS" ]
}

@test "MCP auth structured plans retain multiline explicit config as one argument" {
    local config=$'{\n "mcpServers":{"one":{"url":"https://one.example.invalid/mcp"}}\n}'
    run copilot-launch-plan --no-resume --additional-mcp-config "$config" \
        --mcp-github-auth one=https://one.example.invalid --json
    [ "$status" -eq 0 ]
    jq -e --arg cfg "$config" '.args | index($cfg) != null' <<< "$output"
    [ ! -e "$CALLS" ]
}

@test "MCP auth scopes preserve existing enable disable autoConnect policy" {
    printf '{"mcpServers":{"one":{"autoConnect":["/synthetic/no-match/*"]},"lazy":{"autoConnect":false}}}\n' > "$COPILOT_HOME/mcp-config.json"
    run copilot-launch-plan --no-resume --additional-mcp-config="$CONFIG" \
        --mcp-github-auth=one=https://ONE.example.invalid:443 --enable-mcp-server one \
        --disable-mcp-server two --json
    [ "$status" -eq 0 ]
    jq -e '.args as $a |
        [$a | to_entries[] | select(.value=="--disable-mcp-server") | $a[.key+1]] == ["two"] and
        [$a | to_entries[] | select(.value=="--enable-mcp-server") | $a[.key+1]] == ["one"]' <<< "$output"
    [ ! -e "$CALLS" ]
}
