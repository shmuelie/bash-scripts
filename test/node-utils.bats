#!/usr/bin/env bats
# node-utils.bats — tests for the node-* and utility commands. External tools
# (nvm, npm, dotnet, code, systemctl) are replaced with stubs on PATH.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"; export WORK
    STUB="$WORK/stub"; mkdir -p "$STUB"
    export CALL_LOG="$WORK/calls.log"; : > "$CALL_LOG"
    export PATH="$STUB:$REPO_ROOT/bin:$PATH"
}
teardown() { rm -rf "$WORK"; }

stub() { # stub NAME BODY
    local name="$1" body="$2"
    { echo '#!/usr/bin/env bash'; echo 'printf "%s\n" "$*" >> "$CALL_LOG"'; echo "$body"; } > "$STUB/$name"
    chmod +x "$STUB/$name"
}

# ---- core utilities ------------------------------------------------------

@test "is-elevated reports non-root" {
    run is-elevated
    [ "$status" -eq 1 ]
    [ "$output" = "false" ]
}

@test "in-location runs a command in a directory and returns" {
    mkdir -p "$WORK/target"
    run in-location "$WORK/target" -- pwd
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$WORK/target" && pwd -P)" ]
}

@test "in-location rejects a missing directory" {
    run in-location "$WORK/missing" -- pwd
    [ "$status" -ne 0 ]
}

@test "repair-global-json sets rollForward to disable" {
    cd "$WORK"
    echo '{"sdk":{"version":"8.0.100","rollForward":"latestMinor"}}' > global.json
    run repair-global-json
    [ "$status" -eq 0 ]
    run jq -r '.sdk.rollForward' global.json
    [ "$output" = "disable" ]
}

@test "repair-global-json --dry-run leaves the file unchanged" {
    cd "$WORK"
    echo '{"sdk":{"rollForward":"latestMinor"}}' > global.json
    run repair-global-json --dry-run
    [ "$status" -eq 0 ]
    run jq -r '.sdk.rollForward' global.json
    [ "$output" = "latestMinor" ]
}

# ---- shell-integration (sourced) ----------------------------------------

@test "shell-integration defines a readonly constant and prepends PATH" {
    run bash -c "source '$REPO_ROOT/lib/utils/shell-integration.sh'
        shm_global_constant MYCONST 42
        echo \$MYCONST
        mkdir -p '$WORK/bindir'
        shm_prepend_path '$WORK/bindir'
        case \":\$PATH:\" in *\":$WORK/bindir:\"*) echo onpath;; esac"
    [ "${lines[0]}" = "42" ]
    [ "${lines[1]}" = "onpath" ]
}

# ---- node / nvm ----------------------------------------------------------

@test "node-version delegates to nvm via a sourced nvm.sh" {
    export NVM_DIR="$WORK/nvm"
    mkdir -p "$NVM_DIR"
    cat > "$NVM_DIR/nvm.sh" <<'EOF'
nvm() { printf 'nvm %s\n' "$*" >> "$CALL_LOG"; echo "nvm-called: $*"; }
EOF
    run node-version list
    [ "$status" -eq 0 ]
    grep -q '^nvm ls$' "$CALL_LOG"
}

@test "node-version install passes the version through" {
    export NVM_DIR="$WORK/nvm"; mkdir -p "$NVM_DIR"
    echo 'nvm() { printf "nvm %s\n" "$*" >> "$CALL_LOG"; }' > "$NVM_DIR/nvm.sh"
    run node-version install 22.11.0
    [ "$status" -eq 0 ]
    grep -q '^nvm install 22.11.0$' "$CALL_LOG"
}

@test "node-alias set maps to nvm alias" {
    export NVM_DIR="$WORK/nvm"; mkdir -p "$NVM_DIR"
    echo 'nvm() { printf "nvm %s\n" "$*" >> "$CALL_LOG"; }' > "$NVM_DIR/nvm.sh"
    run node-alias set default 22.11.0
    [ "$status" -eq 0 ]
    grep -q '^nvm alias default 22.11.0$' "$CALL_LOG"
}

@test "nvm-config installed fails when nvm.sh is absent" {
    export NVM_DIR="$WORK/empty"
    run nvm-config installed
    [ "$status" -ne 0 ]
}

@test "nvm-config node-mirror prints an export for a url" {
    run nvm-config node-mirror https://example.com/dist
    [ "$status" -eq 0 ]
    [[ "$output" == "export NVM_NODEJS_ORG_MIRROR="* ]]
}

# ---- npm -----------------------------------------------------------------

@test "npm-package list --outdated --json emits an array" {
    stub npm 'case "$*" in
        "outdated --json --global") echo "{\"typescript\":{\"current\":\"5.0.0\",\"latest\":\"5.4.0\"}}";;
    esac'
    run bash -c "npm-package list --global --outdated --json | jq -c '.[0] | {name, version, latest}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"name":"typescript","version":"5.0.0","latest":"5.4.0"}' ]
}

@test "npm-package update --global uses install -g name@latest" {
    stub npm 'exit 0'
    run npm-package update typescript --global
    [ "$status" -eq 0 ]
    grep -q 'install -g typescript@latest' "$CALL_LOG"
}

@test "npm-package update --dry-run does not call npm" {
    stub npm 'exit 0'
    run npm-package update typescript --global --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"What if:"* ]]
    [ ! -s "$CALL_LOG" ]
}

# ---- dotnet tool ---------------------------------------------------------

@test "dotnet-tool list parses the tool table" {
    stub dotnet 'cat <<TBL
Package Id      Version      Commands
--------------------------------------
dotnet-ef      8.0.0        dotnet-ef
csharpier      0.27.0       dotnet-csharpier
TBL'
    run bash -c "dotnet-tool list --json | jq -c '.[0] | {packageId, version, commands}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"packageId":"dotnet-ef","version":"8.0.0","commands":"dotnet-ef"}' ]
}

@test "dotnet-tool list filters by glob" {
    stub dotnet 'cat <<TBL
Package Id      Version      Commands
--------------------------------------
dotnet-ef      8.0.0        dotnet-ef
csharpier      0.27.0       dotnet-csharpier
TBL'
    run bash -c "dotnet-tool list 'dotnet-*' --json | jq -r 'length'"
    [ "$output" = "1" ]
}

# ---- vscode extensions ---------------------------------------------------

@test "vscode-ext list parses publisher.name@version" {
    stub code 'case "$1" in --list-extensions) printf "ms-python.python@2024.2.0\nesbenp.prettier-vscode@10.1.0\n";; esac'
    run bash -c "vscode-ext list --json | jq -c '.[0] | {publisher, name, version}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"publisher":"ms-python","name":"python","version":"2024.2.0"}' ]
}

@test "vscode-ext install forwards the id and pre-release flag" {
    stub code 'exit 0'
    run vscode-ext install ms-python.python --pre-release
    [ "$status" -eq 0 ]
    grep -q -- '--install-extension ms-python.python --pre-release' "$CALL_LOG"
}

# ---- service-process (systemd stub) -------------------------------------

@test "service-process resolves MainPID via systemctl" {
    stub systemctl 'echo "Id=cron.service"; echo "MainPID=1234"; echo "ActiveState=active"; echo "SubState=running"'
    stub ps 'echo crond'
    run bash -c "service-process cron --json | jq -c '.[0] | {name, processId, state}'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"name":"cron.service","processId":1234,"state":"running"}' ]
}

@test "service-process --pid-only prints the pid" {
    stub systemctl 'echo "Id=cron.service"; echo "MainPID=4321"; echo "ActiveState=active"; echo "SubState=running"'
    stub ps 'echo crond'
    run service-process cron --pid-only
    [ "$output" = "4321" ]
}

# ---- installed-apps ------------------------------------------------------

@test "installed-apps aggregates from a dpkg stub" {
    stub dpkg-query 'printf "bash\t5.1-6\ncoreutils\t8.32-4\n"'
    run bash -c "installed-apps --source dpkg --json | jq -c '.[0]'"
    [ "$status" -eq 0 ]
    [ "$output" = '{"name":"bash","version":"5.1-6","source":"dpkg"}' ]
}
