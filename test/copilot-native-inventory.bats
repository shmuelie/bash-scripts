#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.native-scratch/inventory-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/bin" "$WORK/home"
    export COPILOT_HOME="$WORK/home" CALLS="$WORK/calls"
    export RESPONSE="$WORK/response" NATIVE_STATUS=0
    export JSON_UNSUPPORTED=0
    : > "$RESPONSE"
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
if [[ "$*" == 'plugin list --json' && "$JSON_UNSUPPORTED" == 1 ]]; then
    printf "error: unknown option '--json'\n" >&2
    exit 2
fi
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
    run bash -c '_SHM_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/setup/dev-setup.sh";
        check_plugin_resource "{\"source\":\"new@market\"}"; p=$?;
        check_marketplace_resource "{\"name\":\"market\",\"repository\":\"owner/repo\"}"; m=$?;
        printf "%s %s\n" "$p" "$m"' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '2 2' ]
    ! grep -Eq 'plugin install|marketplace add' "$CALLS"
}

@test "current plugin JSON preserves identities state sources versions and unmanaged entries" {
    cat > "$RESPONSE" <<'EOF'
[{"name":"same","marketplace":"one","version":"1.2.3","enabled":false,"source":"marketplace"},
 {"name":"same","marketplace":"two","version":"2.0","enabled":true,"source":"marketplace"},
 {"name":"same","enabled":true,"source":"builtin"},
 {"name":"local","version":null,"enabled":false,"source":"plugin-dir","installedFrom":"/synthetic/plugin"},
 {"name":"direct","version":"3","enabled":true,"source":"github","installedFrom":"owner/direct"}]
EOF
    run copilot-plugin list --json
    [ "$status" -eq 0 ]
    jq -e 'length==5 and .[0].fullName=="same@one" and .[0].enabled==false and
        .[1].fullName=="same@two" and .[2].managed==false and .[3].managed==false and
        .[3].version=="" and .[4].installedFrom=="owner/direct"' <<< "$output"
    [ "$(wc -l < "$CALLS")" -eq 1 ]
    run copilot-plugin list 'same@two' --json
    [ "$status" -eq 0 ]
    jq -e 'length==1 and .[0].version=="2.0"' <<< "$output"
}

@test "invalid plugin JSON schemas fail atomically without legacy fallback" {
    local fixture
    for fixture in '{}' 'null' '[null]' '[{"name":"x","enabled":true,"source":3}]' \
        '[{"name":"x","enabled":"false","source":"direct"}]' \
        '[{"name":"x","enabled":true,"source":"direct","version":3}]' \
        '[{"name":"x","enabled":true,"source":"direct"},{"name":"bad","source":"direct"}]' \
        '[] []' 'not json'; do
        printf '%s\n' "$fixture" > "$RESPONSE"
        : > "$CALLS"
        run --separate-stderr copilot-plugin list --json
        [ "$status" -ne 0 ]
        [ -z "$output" ]
        [[ "$stderr" == *"invalid JSON or schema"* ]]
        [ "$(wc -l < "$CALLS")" -eq 1 ]
    done
}

@test "recognized unsupported JSON falls back to checked legacy sections and disabled state" {
    export JSON_UNSUPPORTED=1
    cat > "$RESPONSE" <<'EOF'
  • managed@market (v1.0)

Built-in plugins:
  • internal (v2.0) [disabled]

External Plugins (via --plugin-dir):
  • mounted (v3.0)
EOF
    run copilot-plugin list --json
    [ "$status" -eq 0 ]
    jq -e 'length==3 and .[0].managed and .[0].source=="marketplace" and
        .[1].enabled==false and .[1].source=="builtin" and .[1].managed==false and
        .[2].source=="plugin-dir" and .[2].managed==false' <<< "$output"
    [ "$(wc -l < "$CALLS")" -eq 2 ]
    export NATIVE_STATUS=17
    run --separate-stderr copilot-plugin list --json
    [ "$status" -eq 17 ]
    [ -z "$output" ]
}

@test "duplicate plugin installs require exact managed marketplace or direct source" {
    cat > "$RESPONSE" <<'EOF'
[{"name":"same","marketplace":"one","enabled":true,"source":"marketplace"},
 {"name":"same","marketplace":"two","enabled":false,"source":"builtin"},
 {"name":"same","enabled":true,"source":"direct","installedFrom":"other/same"},
 {"name":"mounted","enabled":true,"source":"plugin-dir","installedFrom":"owner/mounted"}]
EOF
    run copilot-plugin install same@one
    [ "$status" -eq 0 ]
    ! grep -q 'plugin install' "$CALLS"
    local source
    for source in same@two owner/same owner/mounted; do
        : > "$CALLS"
        run copilot-plugin install "$source"
        [ "$status" -eq 0 ]
        grep -Fxq "plugin install $source" "$CALLS"
    done
    : > "$CALLS"
    run copilot-plugin install other/same
    [ "$status" -eq 0 ]
    ! grep -q 'plugin install' "$CALLS"
}

@test "unknown direct source is ambiguous and previews never discover or mutate" {
    printf '[{"name":"same","enabled":true,"source":"managed"}]\n' > "$RESPONSE"
    run copilot-plugin install owner/same
    [ "$status" -ne 0 ]
    [[ "$output" == *"did not report its install source"* ]]
    ! grep -q 'plugin install' "$CALLS"
    : > "$CALLS"
    run copilot-plugin install owner/same --dry-run
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "setup plugin checks use exact managed source instead of same-name existence" {
    cat > "$RESPONSE" <<'EOF'
[{"name":"same","marketplace":"one","enabled":true,"source":"marketplace"},
 {"name":"same","enabled":true,"source":"direct","installedFrom":"other/same"}]
EOF
    run bash -c '_SHM_ROOT="$1"; source "$1/lib/common.sh"; source "$1/lib/setup/dev-setup.sh";
        check_plugin_resource "{\"source\":\"same@one\"}"; a=$?;
        check_plugin_resource "{\"source\":\"same@two\"}"; b=$?;
        check_plugin_resource "{\"source\":\"other/same\"}"; c=$?;
        check_plugin_resource "{\"source\":\"owner/same\"}"; d=$?;
        printf "%s %s %s %s\n" "$a" "$b" "$c" "$d"' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '0 1 0 1' ]
}
