#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export RECORD="$WORK/record"
    mkdir "$WORK/bin"
    cp "$REPO_ROOT/test/devtunnel-fake.py" "$WORK/bin/devtunnel"
    chmod +x "$WORK/bin/devtunnel"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
}

teardown() { rm -rf -- "$WORK"; }

expect_args() {
    local expected="$1"; shift
    run dev-tunnel "$@"
    [ "$status" -eq 0 ]
    jq -e --argjson expected "$expected" '. == $expected' < <(tail -n1 "$RECORD")
}

@test "helpers and previews never discover execute install or authenticate" {
    run bash -c 'source "$1/lib/common.sh"; source "$1/lib/devtunnel/devtunnel-common.sh"' -- "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ ! -e "$RECORD" ]
    local operation
    for operation in 'user login' create host connect delete delete-all 'access reset'; do
        # shellcheck disable=SC2086 # intentionally expand the fixed command fixture
        run dev-tunnel $operation --dry-run
        [ "$status" -eq 0 ]
        [[ "$output" == *'What if:'* ]]
    done
    [ ! -e "$RECORD" ]
}

@test "account options and management JSON envelopes are preserved" {
    expect_args '["user","login","--github","--use-device-code-auth"]' user login --github --use-device-code-auth
    expect_args '["user","logout","--json"]' user logout
    expect_args '["user","show","--json"]' user show
    jq -e '.tunnels[0].tunnelId=="fixture" and .continuationToken=="next"' <<< "$output"
}

@test "lifecycle arguments remain literal and use current labels not tags" {
    local value='spaces ; $(touch should-not-exist) "quoted"'
    expect_args "$(jq -cn --arg v "$value" '["create","my-tunnel","--description="+$v,"--labels=web","--labels="+$v,"--expiration=1d","--json"]')" \
        create my-tunnel --description "$value" --labels web --labels "$value" --expiration 1d
    expect_args '["list","--labels=web","--all-labels=team","--limit=3","--json"]' list --labels web --all-labels team --limit 3
    expect_args '["show","--json"]' show
    expect_args '["show","my-tunnel","--json"]' show my-tunnel
    expect_args '["update","--description=","--add-labels=new","--remove-labels=old","--expiration=30d","--json"]' \
        update --description '' --add-labels new --remove-labels old --expiration 30d
    expect_args '["delete","my-tunnel","--json","--force"]' delete my-tunnel --yes
    expect_args '["delete-all","--json","--force"]' delete-all --yes
    expect_args '["set","my-tunnel","--json"]' set my-tunnel
    expect_args '["unset","--json"]' unset
}

@test "host is temporary without an ID and foreground commands never request JSON" {
    expect_args '["host","--port-number=3000","--port-number=5000","--protocol=http","--expiration=1h"]' \
        host --port-number 3000 --port-number 5000 --protocol http --expiration 1h
    expect_args '["host","persistent"]' host persistent
    expect_args '["connect"]' connect
    expect_args '["connect","persistent"]' connect persistent
    expect_args '["echo","http","--port=8080","--interface=127.0.0.1"]' echo --port 8080
    expect_args '["echo","tcp","--port=65535","--interface=::1"]' echo --port 65535 --protocol tcp --interface ::1
    expect_args '["ping","http://localhost:8080/path","--size=64","--interval=1000"]' \
        ping http://localhost:8080/path --size 64 --interval 1000
    expect_args '["clusters","--ping","--json"]' clusters --ping
    expect_args '["limits","--json"]' limits
}

@test "port and access commands map every operation with last-used targeting" {
    expect_args '["port","list","--json"]' port list
    expect_args '["port","show","tunnel","--port-number=3000","--json"]' port show tunnel --port-number 3000
    expect_args '["port","create","--port-number=1","--protocol=auto","--description=web","--labels=demo","--json"]' \
        port create --port-number 1 --protocol auto --description web --labels demo
    expect_args '["port","update","--port-number=3000","--description=","--add-labels=new","--remove-labels=old","--json"]' \
        port update --port-number 3000 --description '' --add-labels new --remove-labels old
    expect_args '["port","delete","--port-number=3000","--json"]' port delete --port-number 3000 --yes
    expect_args '["access","list","--port-number=3000","--json"]' access list --port-number 3000
    expect_args '["access","create","--tenant","--scopes=connect","--scopes=inspect","--expiration=1d","--index=0","--json"]' \
        access create --tenant --scopes connect --scopes inspect --expiration 1d --index 0
    expect_args '["access","create","--organization=example","--json"]' access create --organization example
    expect_args '["access","create","--repo=owner/repo","--deny","--json"]' access create --repo owner/repo --deny
    expect_args '["access","delete","--index=0","--json"]' access delete --index 0 --yes
    expect_args '["access","reset","--json"]' access reset --yes
}

@test "anonymous access is never implicit and explicit opt-in warns" {
    run dev-tunnel create
    [ "$status" -eq 0 ]
    [[ "$output" != *Anonymous* ]]
    run dev-tunnel host --allow-anonymous
    [ "$status" -eq 0 ]
    [[ "$output" == *'anyone on the internet'* ]]
    run dev-tunnel access create --anonymous
    [ "$status" -eq 0 ]
    [[ "$output" == *'anyone on the internet'* ]]
    run dev-tunnel access create --anonymous --deny
    [ "$status" -eq 0 ]
    [[ "$output" != *'anyone on the internet'* ]]
}

@test "destructive operations require intentional approval before CLI discovery" {
    local operation
    for operation in delete delete-all 'access reset' 'access delete --index 0' 'port delete --port-number 3000'; do
        # shellcheck disable=SC2086 # intentionally expand the fixed command fixture
        run dev-tunnel $operation </dev/null
        [ "$status" -ne 0 ]
        [[ "$output" == *'explicit --yes'* ]]
    done
    [ ! -e "$RECORD" ]
    run dev-tunnel create --confirm </dev/null
    [ "$status" -ne 0 ]
    [ ! -e "$RECORD" ]
}

@test "input validation fails before any CLI discovery or preview effects" {
    local fixture
    for fixture in \
        'host --port-number 0' 'host --port-number 65536' 'host --protocol tcp' \
        'create --expiration 0h' 'create --expiration 721h' 'create --expiration 31d' \
        'create --tags old' 'create --labels=' 'create --description=' \
        'port create' 'port show --port-number -1' 'set' \
        'access create' 'access create --anonymous --tenant' 'access delete' \
        'access create --tenant --scopes admin' 'access delete --index -1' \
        'echo --port 8080 --interface invalid' 'echo --port 8080 --protocol auto' \
        'ping /relative' 'ping file:///local' 'ping https://user:password@localhost' \
        'token --scopes connect' 'token --show-token' 'host --json' 'list --timeout 0'; do
        # shellcheck disable=SC2086 # intentionally expand the fixed command fixture
        run dev-tunnel $fixture --dry-run
        [ "$status" -ne 0 ]
    done
    [ ! -e "$RECORD" ]
}

@test "version compatibility and failures never fall through to an operation" {
    local version
    for version in 1.0.2114 2.0.0 unknown; do
        export FAKE_VERSION="$version"
        run dev-tunnel list
        [ "$status" -ne 0 ]
        [ "$(tail -n1 "$RECORD")" = '["--version"]' ]
    done
    export FAKE_VERSION='Tunnel CLI version: 1.1.0'
    run dev-tunnel version
    [ "$status" -eq 0 ]
    jq -e '.version=="1.1.0" and (.path|endswith("/devtunnel"))' <<< "$output"
    export FAKE_VERSION_STATUS=17
    run dev-tunnel list
    [ "$status" -eq 17 ]
    [ "$(tail -n1 "$RECORD")" = '["--version"]' ]
}

@test "missing CLI is actionable and dry-run works without it" {
    rm "$WORK/bin/devtunnel"
    run dev-tunnel list
    [ "$status" -ne 0 ]
    [[ "$output" == *'not found on PATH'* ]]
    [[ "$output" == *'Install Microsoft devtunnel'* ]]
    run dev-tunnel host --dry-run
    [ "$status" -eq 0 ]
}

@test "native exit stderr malformed JSON and empty responses remain explicit" {
    export FAKE_STATUS=23 FAKE_ERROR='fixture service failure'
    run dev-tunnel list
    [ "$status" -eq 23 ]
    [[ "$output" == *'fixture service failure'* ]]
    export FAKE_STATUS=0 FAKE_ERROR='fixture warning'
    run dev-tunnel list
    [ "$status" -eq 0 ]
    [[ "$output" == *'Warning: fixture warning'* ]]
    export FAKE_ERROR='' FAKE_OUTPUT=not-json
    run dev-tunnel list
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid JSON'* ]]
    [[ "$output" != *not-json* ]]
    export FAKE_OUTPUT=''
    run dev-tunnel list
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "token credentials require explicit stdout consent or a private new file" {
    export FAKE_OUTPUT='{"token":"fixture-secret"}'
    run dev-tunnel token tunnel --scopes connect --output-file "$WORK/token"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(stat -c %a "$WORK/token")" = 600 ]
    jq -e '.token=="fixture-secret"' "$WORK/token"
    run dev-tunnel token --scopes connect --output-file "$WORK/token"
    [ "$status" -ne 0 ]
    ln -s "$WORK/token" "$WORK/link"
    run dev-tunnel token --scopes connect --output-file "$WORK/link"
    [ "$status" -ne 0 ]
    expect_args '["token","--scopes=connect","--json"]' token --scopes connect --show-token
    export FAKE_OUTPUT=malformed-secret FAKE_ERROR=fixture-secret FAKE_STATUS=9
    run dev-tunnel token --scopes connect --show-token
    [ "$status" -eq 9 ]
    [[ "$output" != *fixture-secret* ]]
    [[ "$output" != *malformed-secret* ]]
}

@test "foreground credentials are redacted while device instructions stream" {
    export FAKE_OUTPUT=$'Open browser and enter code ABCD.\nAuthorization: Bearer fixtureSecret\naccess_token=fixtureAccess\n'
    export FAKE_ERROR='refresh_token=fixtureRefresh'
    run dev-tunnel user login --use-device-code-auth
    [ "$status" -eq 0 ]
    [[ "$output" == *'enter code ABCD'* ]]
    [[ "$output" == *'[REDACTED]'* ]]
    [[ "$output" != *fixtureSecret* ]]
    [[ "$output" != *fixtureAccess* ]]
    [[ "$output" != *fixtureRefresh* ]]
    [ "$(grep -c 'enter code' <<< "$output")" -eq 1 ]
}

@test "management timeout and cancellation clean up only owned processes" {
    run python3 "$REPO_ROOT/test/devtunnel-process.py" "$REPO_ROOT/bin/dev-tunnel" "$WORK"
    [ "$status" -eq 0 ]
}
