#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export REPO_ROOT WORK CALL_LOG="$WORK/calls" SDK_RESOLVED_VERSION=8.0.412
    export SDK_INSTALLER_FIXTURE="$REPO_ROOT/test/fixtures/packages/dotnet-install.sh"
    mkdir "$WORK/bin" "$WORK/tmp"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH" TMPDIR="$WORK/tmp"
    : > "$CALL_LOG"
    unset SDK_INSTALL_FAIL SDK_GPG_FAIL SDK_HTTP_STATUS SDK_EMPTY_INSTALL SDK_HOST_FAIL SDK_DUPLICATE_RESOLUTION
    stub curl '
        out=""; url=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --output) out="$2"; shift 2;;
                --write-out|--proto) shift 2;;
                --tlsv1.2|--fail|--silent|--show-error) shift;;
                https://builds.dotnet.microsoft.com/dotnet/scripts/v1/*) url="$1"; shift;;
                *) exit 99;;
            esac
        done
        [[ -n "$url" && -n "$out" ]] || exit 98
        if [[ "$url" == */dotnet-install.sh ]]; then cp "$SDK_INSTALLER_FIXTURE" "$out"
        else printf "fixture\n" > "$out"; fi
        printf "%s" "${SDK_HTTP_STATUS:-200}"
    '
    stub gpg '[[ "$*" != *--verify* || "${SDK_GPG_FAIL:-0}" == 0 ]] || exit "$SDK_GPG_FAIL"'
    # A copied Bash binary gives a genuine architecture header. Its 'exec'
    # script checks the exact SDK path without launching a real dotnet host.
    cat > "$WORK/exec" <<'EOF'
printf 'host:%s\n' "$*" >> "$CALL_LOG"
[[ "$1" == */sdk/"$SDK_RESOLVED_VERSION"/dotnet.dll && "$2" == --version ]] || exit 96
[[ "${SDK_HOST_FAIL:-0}" == 0 ]] || exit "$SDK_HOST_FAIL"
printf '%s\n' "$SDK_RESOLVED_VERSION"
EOF
    cd "$WORK"
}

teardown() { rm -rf "$WORK"; }

stub() {
    printf '#!/usr/bin/env bash\nprintf "%s:%%s\\n" "$*" >> "$CALL_LOG"\n%s\n' "$1" "$2" > "$WORK/bin/$1"
    chmod +x "$WORK/bin/$1"
}

install_sdk() {
    local result=0
    dotnet-sdk-install --install-dir "$WORK/sdk dir" --json "$@" > "$WORK/result.json" 2> "$WORK/errors" || result=$?
    if [[ "$result" != 0 ]]; then cat "$WORK/errors" "$WORK/result.json"; fi
    return "$result"
}

@test "SDK exact install authenticates canonical content with an isolated keyring and no PATH change" {
    original="$PATH"
    run install_sdk --version 8.0.412
    [ "$status" -eq 0 ]
    [ "$(jq -r '.status' "$WORK/result.json")" = Installed ]
    [ "$(jq -r '.processPathChanged' "$WORK/result.json")" = false ]
    [ "$PATH" = "$original" ]
    [ "$(grep -c '^curl:' "$CALL_LOG")" -eq 3 ]
    grep -q 'gpg:--batch --no-options --homedir .*keyring --no-autostart --verify' "$CALL_LOG"
    grep -q 'installer:.*--no-path.*--version 8.0.412' "$CALL_LOG"
    grep -qx "host:$WORK/sdk dir/sdk/8.0.412/dotnet.dll --version" "$CALL_LOG"
    [ -z "$(find "$WORK/tmp" -mindepth 1 -print -quit)" ]
}

@test "SDK matching version reuses existing files without installer downloads" {
    run install_sdk --version 8.0.412
    [ "$status" -eq 0 ]
    : > "$CALL_LOG"
    run install_sdk --version 8.0.412
    [ "$status" -eq 0 ]
    [ "$(jq -r '.status' "$WORK/result.json")" = AlreadyInstalled ]
    ! grep -q 'curl:\|installer:' "$CALL_LOG"
    grep -q '^host:' "$CALL_LOG"
}

@test "SDK default installation is user-local and does not follow ambient installer directory" {
    mkdir "$WORK/home"
    export HOME="$WORK/home" DOTNET_INSTALL_DIR="$WORK/unrelated"
    run dotnet-sdk-install --version 8.0.412 --json
    [ "$status" -eq 0 ]
    [ -f "$WORK/home/.dotnet/sdk/8.0.412/dotnet.dll" ]
    [ ! -e "$WORK/unrelated" ]
    [ "$(jq -r .installDir <<< "$output")" = "$WORK/home/.dotnet" ]
}

@test "SDK channel resolution forwards quality and pins the validated exact version" {
    export SDK_RESOLVED_VERSION=9.0.100-preview.2
    run install_sdk --channel 9.0 --quality preview --architecture amd64
    [ "$status" -eq 0 ]
    [ "$(jq -r '.resolvedVersion' "$WORK/result.json")" = 9.0.100-preview.2 ]
    grep -q 'installer:.*--channel 9.0 --dry-run --quality preview' "$CALL_LOG"
    grep -q 'installer:.*--version 9.0.100-preview.2' "$CALL_LOG"
    [ "$(jq -r '.requestedChannel' "$WORK/result.json")" = 9.0 ]
}

@test "SDK preview independently gates installer and PATH without staging or calls" {
    run install_sdk --channel LTS --dry-run --add-to-process-path
    [ "$status" -eq 0 ]
    [ "$(jq -r '.status' "$WORK/result.json")" = Skipped ]
    [ "$(jq -r '.resolvedVersion' "$WORK/result.json")" = null ]
    [ "$(jq -r '.processPathChanged' "$WORK/result.json")" = false ]
    [ "$(grep -c 'What if:' "$WORK/errors")" -eq 3 ]
    [ ! -s "$CALL_LOG" ]
    [ ! -e "$WORK/sdk dir" ]
    [ -z "$(find "$WORK/tmp" -mindepth 1 -print -quit)" ]
}

@test "SDK rejects failed authenticity HTTP redirects and invalid resolution before install" {
    export SDK_GPG_FAIL=42
    run install_sdk --version 8.0.412
    [ "$status" -eq 42 ]
    [ ! -e "$WORK/sdk dir" ]
    ! grep -q '^installer:' "$CALL_LOG"
    [ -z "$(find "$WORK/tmp" -mindepth 1 -print -quit)" ]
    unset SDK_GPG_FAIL
    export SDK_HTTP_STATUS=302
    run install_sdk --version 8.0.412
    [ "$status" -ne 0 ]
    ! grep -q '^installer:' "$CALL_LOG"
    unset SDK_HTTP_STATUS
    export SDK_DUPLICATE_RESOLUTION=1
    run install_sdk --channel LTS
    [ "$status" -ne 0 ]
    [ ! -e "$WORK/sdk dir" ]
}

@test "SDK installer failures and success without installed files are errors" {
    export SDK_INSTALL_FAIL=42
    run install_sdk --version 8.0.412 --add-to-process-path
    [ "$status" -eq 42 ]
    [ ! -s "$WORK/result.json" ]
    unset SDK_INSTALL_FAIL
    export SDK_EMPTY_INSTALL=1
    run install_sdk --version 8.0.412
    [ "$status" -ne 0 ]
    [ ! -s "$WORK/result.json" ]
    [ -z "$(find "$WORK/tmp" -mindepth 1 -print -quit)" ]
}

@test "SDK preserves an existing host regardless of SDK feature-band ordering" {
    run install_sdk --version 8.0.412
    [ "$status" -eq 0 ]
    before="$(sha256sum "$WORK/sdk dir/dotnet")"
    export SDK_RESOLVED_VERSION=8.0.100
    run install_sdk --version 8.0.100
    [ "$status" -eq 0 ]
    [ "$before" = "$(sha256sum "$WORK/sdk dir/dotnet")" ]
    grep -q 'installer:.*--version 8.0.100 --skip-non-versioned-files' "$CALL_LOG"
    export SDK_RESOLVED_VERSION=9.0.100
    run install_sdk --version 9.0.100
    [ "$status" -eq 0 ]
    grep -q 'installer:.*--version 9.0.100 --skip-non-versioned-files' "$CALL_LOG"
    [ "$before" = "$(sha256sum "$WORK/sdk dir/dotnet")" ]
}

@test "SDK incompatible host and architecture mismatches fail without PATH success" {
    run install_sdk --version 8.0.412
    [ "$status" -eq 0 ]
    : > "$CALL_LOG"
    run install_sdk --version 8.0.412 --architecture arm64
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
    export SDK_HOST_FAIL=42
    run install_sdk --version 8.0.412 --add-to-process-path
    [ "$status" -eq 42 ]
    [ ! -s "$WORK/result.json" ]
}

@test "SDK sourceable helper changes only the caller process PATH and does not duplicate it" {
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/utils/dotnet-sdk.sh"
        shm_install_dotnet_sdk --version 8.0.412 --install-dir "$WORK/sdk dir" --add-to-process-path --json > "$WORK/first.json" || exit
        [[ "$PATH" == "$WORK/sdk dir:"* ]] || exit 91
        shm_install_dotnet_sdk --version 8.0.412 --install-dir "$WORK/sdk dir" --add-to-process-path --json > "$WORK/second.json"
    '
    [ "$status" -eq 0 ]
    [ "$(jq -r '.processPathChanged' "$WORK/first.json")" = true ]
    [ "$(jq -r '.processPathChanged' "$WORK/second.json")" = false ]
    [[ "$PATH" != "$WORK/sdk dir:"* ]]
}

@test "SDK readonly PATH and unsupported persistent integration fail before mutations" {
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/utils/dotnet-sdk.sh"
        readonly PATH
        shm_install_dotnet_sdk --version 8.0.412 --install-dir "$WORK/sdk dir" --add-to-process-path --json
    '
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
    [ ! -e "$WORK/sdk dir" ]
    run install_sdk --version 8.0.412 --add-to-user-path
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
}

@test "SDK environment write failure cannot emit successful PATH changes" {
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/utils/dotnet-sdk.sh"
        export() { return 42; }
        shm_install_dotnet_sdk --version 8.0.412 --install-dir "$WORK/sdk dir" --add-to-process-path --json > "$WORK/write-failure.json"
    '
    [ "$status" -ne 0 ]
    [ ! -s "$WORK/write-failure.json" ]
    [[ "$output" == *"Failed to update process PATH."* ]]
}

@test "SDK installation and process PATH approval can be declined independently" {
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/utils/dotnet-sdk.sh"
        dotnet_sdk_approve() { [[ "$1" != Install* ]]; }
        shm_install_dotnet_sdk --version 8.0.412 --install-dir "$WORK/sdk dir" --add-to-process-path --json > "$WORK/declined.json"
    '
    [ "$status" -eq 0 ]
    [ "$(jq -r '.status' "$WORK/declined.json")" = Skipped ]
    [ "$(jq -r '.processPathChanged' "$WORK/declined.json")" = false ]
    [ ! -e "$WORK/sdk dir" ]
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/utils/dotnet-sdk.sh"
        dotnet_sdk_approve() { [[ "$1" != Add* ]]; }
        shm_install_dotnet_sdk --version 8.0.412 --install-dir "$WORK/sdk dir" --add-to-process-path --json > "$WORK/declined-path.json"
    '
    [ "$status" -eq 0 ]
    [ "$(jq -r '.status' "$WORK/declined-path.json")" = Installed ]
    [ "$(jq -r '.processPathChanged' "$WORK/declined-path.json")" = false ]
}

@test "SDK rejects invalid version channel quality directory and architecture before native calls" {
    for args in '--version 8.0' '--channel 4.0 --quality preview' '--quality GA' \
        '--version 8.0.412 --channel LTS' '--architecture invalid'; do
        read -r -a arguments <<< "$args"
        run install_sdk "${arguments[@]}"
        [ "$status" -ne 0 ]
    done
    run dotnet-sdk-install --install-dir "$WORK/not:a:path" --version 8.0.412 --dry-run
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
}
