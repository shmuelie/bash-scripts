#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.native-scratch/inventory-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/bin" "$WORK/home"
    export COPILOT_HOME="$WORK/home" CALLS="$WORK/calls"
    export RESPONSE="$WORK/response" NATIVE_STATUS=0
    : > "$RESPONSE"
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
cat "$RESPONSE"
exit "$NATIVE_STATUS"
EOF
    chmod +x "$WORK/bin/copilot"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
}

teardown() { rm -rf -- "$WORK"; }

@test "all native readers discard valid partial inventory on failure and retain diagnostics" {
    printf '  • synthetic@market (v1.2.3)\n  ◆ market (GitHub: owner/repo)\n  • synthetic - description\nsynthetic native error\n' > "$RESPONSE"
    export NATIVE_STATUS=17
    local cmd
    for cmd in 'copilot-plugin list' 'copilot-marketplace list' 'copilot-marketplace browse market'; do
        run --separate-stderr bash -c "$cmd --json"
        [ "$status" -eq 17 ]
        [ -z "$output" ]
        [[ "$stderr" == *"exit 17"* ]]
        [[ "$stderr" == *"synthetic native error"* ]]
    done
}

@test "all native readers accept successful empty inventories" {
    local cmd
    for cmd in 'copilot-plugin list' 'copilot-marketplace list' 'copilot-marketplace browse market'; do
        run bash -c "$cmd --json"
        [ "$status" -eq 0 ]
        [ "$output" = '[]' ]
    done
}

@test "plugin install stops before mutation when discovery fails" {
    export NATIVE_STATUS=17
    printf '  • existing@market (v1.0.0)\nsynthetic error\n' > "$RESPONSE"
    run copilot-plugin install new@market
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$CALLS")" -eq 1 ]
    ! grep -q 'plugin install' "$CALLS"
}

@test "marketplace registration stops on failed discovery and skips exact existing source" {
    export NATIVE_STATUS=17
    run copilot-marketplace add owner/repo
    [ "$status" -eq 17 ]
    ! grep -q 'marketplace add' "$CALLS"
    export NATIVE_STATUS=0
    printf '  ◆ market (GitHub: owner/repo)\n' > "$RESPONSE"
    run copilot-marketplace add owner/repo
    [ "$status" -eq 0 ]
    ! grep -q 'marketplace add' "$CALLS"
}

@test "setup existence checks report failed discovery rather than absence" {
    export NATIVE_STATUS=17
    run bash -c 'source "$1/lib/common.sh"; source "$1/lib/setup/dev-setup.sh";
        check_plugin_resource "{\"source\":\"new@market\"}"; p=$?;
        check_marketplace_resource "{\"name\":\"market\",\"repository\":\"owner/repo\"}"; m=$?;
        printf "%s %s\n" "$p" "$m"' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '2 2' ]
    ! grep -Eq 'plugin install|marketplace add' "$CALLS"
}
