#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.native-scratch/routing-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/bin" "$WORK/home"
    export COPILOT_HOME="$WORK/home" CALLS="$WORK/calls"
    cat > "$WORK/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$CALLS"
EOF
    cat > "$WORK/bin/pwsh" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected PowerShell resolution\n' >> "$CALLS"
exit 99
EOF
    chmod +x "$WORK/bin/"*
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
}

teardown() { rm -rf -- "$WORK"; }

@test "fleet bare and typed prompts map to autopilot while interactive remains interactive" {
    local option
    for option in --prompt -p; do
        run copilot-launch-plan --no-resume --fleet "$option" 'synthetic task' --json
        [ "$status" -eq 0 ]
        jq -e '.args | index("--fleet") != null and index("--autopilot") != null and index("synthetic task") != null' <<< "$output"
    done
    run copilot-launch-plan --no-resume --fleet 'synthetic task' --json
    [ "$status" -eq 0 ]
    local option
    for option in --interactive -i; do
        run copilot-launch-plan --no-resume --fleet "$option" 'synthetic interactive' --json
        [ "$status" -eq 0 ]
        jq -e '.args | index("--fleet") != null and index("--interactive") != null and index("--autopilot") == null' <<< "$output"
    done
    [ ! -e "$CALLS" ]
}

@test "Auto tiers validate model combinations and repeated retrieval settings preserve order" {
    local tier
    for tier in efficiency balance intelligence; do
        run copilot-launch-plan --no-resume --auto-tier "$tier" --model auto \
            --dynamic-retrieval skills=on --dynamic-retrieval skills=off --no-mouse --json
        [ "$status" -eq 0 ]
        jq -e --arg tier "$tier" '.args as $a |
            $a[($a | index("--auto-tier"))+1] == $tier and
            [$a[] | select(startswith("skills="))] == ["skills=on","skills=off"] and
            ($a | index("--no-mouse")) != null' <<< "$output"
    done
    run copilot-launch-plan --no-resume --auto-tier balance --json
    [ "$status" -eq 0 ]
    run copilot-launch-plan --no-resume --auto-tier=balance --model=auto \
        --dynamic-retrieval=skills=on --mouse=off --json
    [ "$status" -eq 0 ]
    [ ! -e "$CALLS" ]
}

@test "invalid routing combinations and values fail before native launch or preview" {
    local flags
    for flags in '--fleet' '--auto-tier balance --model explicit' '--auto-tier fast' \
        '--auto-tier=balance --model=explicit' '--auto-tier=fast' \
        '--dynamic-retrieval skills=auto' '--dynamic-retrieval tools=on' \
        '--mouse on --no-mouse' '--mouse off --no-mouse' '--mouse auto' \
        '--prompt initial --interactive other'; do
        run bash -c "start-copilot --no-resume --dry-run $flags"
        [ "$status" -ne 0 ]
    done
    local option
    for option in --auto-tier --dynamic-retrieval --mouse --prefer-version --interactive --prompt; do
        run start-copilot --no-resume "$option"
        [ "$status" -ne 0 ]
        [[ "$output" == *"requires"* ]]
    done
    [ ! -e "$CALLS" ]
}

@test "prefer-version reasoning summaries hidden compatibility retain native forwarding" {
    run copilot-launch-plan --no-resume --prefer-version 1.0.synthetic --enable-reasoning-summaries --json
    [ "$status" -eq 0 ]
    jq -e '.args | index("--prefer-version") != null and
        index("1.0.synthetic") != null and index("--enable-reasoning-summaries") != null and
        ([.[] | select(.=="--no-auto-update")] | length==1)' <<< "$output"
    run copilot-launch-plan --no-resume --prefer-version 1.0.synthetic --no-auto-update --json
    [ "$status" -eq 0 ]
    jq -e '[.args[] | select(.=="--no-auto-update")] | length==1' <<< "$output"
    [ ! -e "$CALLS" ]
}

@test "help update passthrough bypasses routing combination guards and Linux no-eager never resolves pwsh" {
    local command
    for command in help update; do
        run copilot-launch-plan "$command" --fleet --auto-tier balance --model explicit \
            --mouse on --no-mouse --no-eager-powershell-resolution --json
        [ "$status" -eq 0 ]
        jq -e --arg cmd "$command" '.passthrough==true and .args[0]==$cmd and
            (.args | index("--experimental"))==null' <<< "$output"
    done
    run start-copilot --no-resume --no-eager-powershell-resolution --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"only supported on Windows"* ]]
    [ ! -e "$CALLS" ]
}

@test "wrappers preserve option-spelled values and arbitrary post-double-dash native flags" {
    run start-copilot --no-resume --interactive --dry-run --passthru
    [ "$status" -eq 0 ]
    [[ "$output" == *"--interactive --dry-run"* ]]
    run copilot-launch-plan --no-resume --prefer-version --json --json
    [ "$status" -eq 0 ]
    jq -e '.args as $a | $a[($a | index("--prefer-version"))+1]=="--json"' <<< "$output"
    run copilot-launch-plan --no-resume --json -- --fleet --dynamic-retrieval future=on
    [ "$status" -eq 0 ]
    jq -e '.args[-3:]==["--fleet","--dynamic-retrieval","future=on"]' <<< "$output"
    [ ! -e "$CALLS" ]
}
