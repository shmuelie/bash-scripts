#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-work-install-deps-${BATS_TEST_NUMBER:-0}-$$"
    rm -rf "$WORK"
    mkdir -p "$WORK/stub" "$WORK/deps"
    STUB="$WORK/stub"
    DEPS="$WORK/deps"
    PREFIX="$WORK/bin"
    RC="$WORK/rc"
    CALL_LOG="$WORK/calls.log"
    : > "$CALL_LOG"

    ln -s "$(command -v bash)" "$DEPS/bash"
    ln -s "$(command -v git)" "$DEPS/git"
    export SHM_INSTALL_DEP_PATH="$DEPS"
    export CALL_LOG DEPS
    export PATH="$STUB:$PATH"
}

teardown() {
    rm -rf "$WORK"
}

stub_manager() {
    local name="$1"
    cat > "$STUB/$name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALL_LOG"
touch "$DEPS/jq"
exit "${PACKAGE_EXIT:-0}"
EOF
    chmod +x "$STUB/$name"
}

stub_id() {
    cat > "$STUB/id" <<EOF
#!/usr/bin/env bash
printf '%s\n' '${1:-0}'
EOF
    chmod +x "$STUB/id"
}

@test "required dependency installation detects apt and maps jq" {
    stub_manager apt-get
    stub_id 0

    run "$REPO_ROOT/install.sh" --install-deps --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected package manager: apt"* ]]
    [[ "$output" == *"DEBIAN_FRONTEND=noninteractive"*"apt-get update"* ]]
    [[ "$output" == *"apt-get install -y jq"* ]]
    grep -qx 'update' "$CALL_LOG"
    grep -qx 'install -y jq' "$CALL_LOG"
}

@test "dry-run shows the exact command without invoking the manager" {
    stub_manager pacman
    stub_id 0
    export SHM_INSTALL_PACKAGE_MANAGER=pacman

    run "$REPO_ROOT/install.sh" --install-deps --dry-run --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -ne 0 ]
    [[ "$output" == *"pacman -S --needed --noconfirm jq"* ]]
    [[ "$output" == *"Dry run:"* ]]
    [ ! -s "$CALL_LOG" ]
}

@test "system package managers use sudo only for non-root users" {
    stub_manager dnf
    stub_id 1000
    export SHM_INSTALL_PACKAGE_MANAGER=dnf
    cat > "$STUB/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo:%s\n' "$*" >> "$CALL_LOG"
"$@"
EOF
    chmod +x "$STUB/sudo"

    run "$REPO_ROOT/install.sh" --install-deps --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo "*"dnf install -y jq"* ]]
    grep -q '^sudo:.*dnf install -y jq$' "$CALL_LOG"
}

@test "brew never uses sudo" {
    stub_manager brew
    stub_id 1000
    export SHM_INSTALL_PACKAGE_MANAGER=brew

    run "$REPO_ROOT/install.sh" --install-deps --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -eq 0 ]
    [[ "$output" == *"brew install jq"* ]]
    [[ "$output" != *"sudo brew"* ]]
}

@test "unsupported package manager reports missing required dependencies" {
    export SHM_INSTALL_PACKAGE_MANAGER=unsupported
    run "$REPO_ROOT/install.sh" --install-deps --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -ne 0 ]
    [[ "$output" == *"No supported package manager found"* ]]
    [[ "$output" == *"jq not found (required)"* ]]
}

@test "all maps development packages and reports manual tools" {
    stub_manager apt
    stub_id 0
    export SHM_INSTALL_PACKAGE_MANAGER=apt

    run "$REPO_ROOT/install.sh" --install-deps --deps all --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -eq 0 ]
    grep -q 'shellcheck' "$CALL_LOG"
    grep -q 'bats' "$CALL_LOG"
    grep -q 'nodejs' "$CALL_LOG"
    [[ "$output" == *"Manual dependency: dotnet"* ]]
    [[ "$output" == *"Manual dependency: code"* ]]
}

@test "package-manager partial failure is returned after dependency recheck" {
    stub_manager zypper
    stub_id 0
    export SHM_INSTALL_PACKAGE_MANAGER=zypper
    export PACKAGE_EXIT=7

    run "$REPO_ROOT/install.sh" --install-deps --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -ne 0 ]
    [[ "$output" == *"package-manager command failed"* ]]
    [ -e "$DEPS/jq" ]
}
