#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export REPO_ROOT WORK CALL_LOG="$WORK/calls"
    mkdir "$WORK/bin"
    : > "$CALL_LOG"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    # Every optional integration is shadowed, so no real inventory/update runs.
    for tool in npm pip uv dotnet code pwsh; do stub "$tool" 'echo "Unexpected native invocation" >&2; exit 99'; done
}

teardown() { rm -rf "$WORK"; }

stub() {
    printf '#!/usr/bin/env bash\nprintf "%%s:%%s\\n" "%s" "$*" >> "$CALL_LOG"\n%s\n' "$1" "$2" > "$WORK/bin/$1"
    chmod +x "$WORK/bin/$1"
}

aggregate() {
    local result=0
    package-update "$@" --json > "$WORK/results.json" 2> "$WORK/errors" || result=$?
    if [[ "$result" != 0 ]]; then cat "$WORK/errors" "$WORK/results.json"; fi
    return "$result"
}

@test "core fake providers continue independent targets and honor fail-fast" {
    for stop in 0 1; do
        run bash -c '
            source "$REPO_ROOT/lib/common.sh"
            source "$REPO_ROOT/lib/packages/core.sh"
            available() { return 0; }
            missing() { echo "optional integration absent"; return 1; }
            discover() { echo "[{\"target\":\"bad\",\"version\":\"1\"},{\"target\":\"good\",\"version\":\"1\"}]"; }
            update() {
                if [[ $(jq -r .target <<< "$1") == bad ]]; then echo native-failure >&2; return 42; fi
                echo "{\"resultingVersion\":\"2\"}"
            }
            packages_register fake available discover update
            packages_register absent missing discover update
            PACKAGES_STOP_ON_FAILURE="$1"
            packages_run "{}" fake absent > "$WORK/results.json"
        ' _ "$stop"
        [ "$status" -eq 1 ]
        if [ "$stop" = 0 ]; then
            [ "$(jq -rs 'map(.status) | join(",")' "$WORK/results.json")" = 'Failed,Updated,Skipped' ]
        else
            [ "$(jq -s length "$WORK/results.json")" -eq 1 ]
        fi
    done
}

@test "core rejects invalid discovery and unknown outcomes instead of claiming unchanged" {
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/packages/core.sh"
        available() { return 0; }
        invalid() { echo "not JSON"; }
        discover() { echo "[{\"target\":\"demo\",\"version\":\"1\"}]"; }
        update() { echo "{}"; }
        packages_register invalid available invalid update
        packages_register unknown available discover update
        packages_run "{}" invalid unknown > "$WORK/results.json"
    '
    [ "$status" -eq 1 ]
    [ "$(jq -rs 'map(.status) | join(",")' "$WORK/results.json")" = 'Failed,Failed' ]
}

@test "core confirmation decline is skipped and previews never call updates" {
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/packages/core.sh"
        available() { return 0; }
        discover() { echo "[{\"target\":\"demo\",\"version\":\"1\"}]"; }
        update() { echo mutation >> "$CALL_LOG"; return 99; }
        packages_register fake available discover update
        packages_approve() { return 1; }
        packages_run "{}" fake > "$WORK/results.json"
        DRY_RUN=1
        packages_run "{}" fake >> "$WORK/results.json"
    '
    [ "$status" -eq 0 ]
    [ "$(jq -rs 'map(.status) | join(",")' "$WORK/results.json")" = 'Skipped,Preview' ]
    [ ! -s "$CALL_LOG" ]
}

@test "explicit inclusion and exclusion never discover unrelated providers" {
    run aggregate --provider dotnet --exclude-provider dotnet
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/results.json")" = '[]' ]
    [ ! -s "$CALL_LOG" ]
    run aggregate --provider npm --options '{"vscode":{"profiles":["--unsafe"]}}'
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
    run aggregate --provider npm --options '{"pip":{"user":"yes"}}'
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
    run aggregate --provider dotnet --options '{"dotnet":{"name":"--local"}}'
    [ "$status" -ne 0 ]
    [ ! -s "$CALL_LOG" ]
}

@test "all registered providers are selected by default and absent integrations stay skipped" {
    stub npm 'echo "{}"'
    stub pip 'echo "[]"'
    stub dotnet 'exit 0'
    stub uv '[[ "$1" != pip ]] || echo "[]"'
    stub code 'exit 0'
    run aggregate
    [ "$status" -eq 0 ]
    [ "$(jq -r 'map(.provider)|join(",")' "$WORK/results.json")" = npm,pip,dotnet,uv,vscode,psresource ]
    [ "$(jq -r '[.[]|select(.provider=="dotnet" or .provider=="psresource")|.status]|join(",")' "$WORK/results.json")" = Skipped,Skipped ]
    ! grep -q '^pwsh:' "$CALL_LOG"
    run bash -c '
        source "$REPO_ROOT/lib/common.sh"; source "$REPO_ROOT/lib/utils/package-validation.sh"
        source "$REPO_ROOT/lib/packages/core.sh"; source "$REPO_ROOT/lib/packages/providers.sh"
        have_cmd() { return 1; }
        packages_run "{}" npm pip dotnet uv vscode > "$WORK/missing.json"
    '
    [ "$status" -eq 0 ]
    [ "$(jq -rs 'all(.[]; .status=="Skipped" and (.reason|length>0))' "$WORK/missing.json")" = true ]
}

@test "npm aggregate preserves scoped names and observes actual global versions" {
    stub npm 'case "$1" in
        outdated) echo "{\"@scope/tool\":{\"current\":\"1\",\"latest\":\"9\"}}"; exit 1;;
        install) touch "$WORK/updated";;
        list) echo "{\"dependencies\":{\"@scope/tool\":{\"version\":\"2\"}}}";;
        *) exit 99;;
    esac'
    run aggregate --provider npm --dry-run
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Preview ]
    [ ! -e "$WORK/updated" ]
    run aggregate --provider npm
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0] | [.status,.previousVersion,.proposedVersion,.resultingVersion] | join(",")' "$WORK/results.json")" = Updated,1,9,2 ]
    grep -qx 'npm:install -g @scope/tool@latest' "$CALL_LOG"
    ! grep -q -- '--local' "$CALL_LOG"
}

@test "npm fatal discovery and failed updates cannot turn into empty or unchanged success" {
    stub npm 'exit 42'
    run aggregate --provider npm
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
    stub npm 'case "$1" in outdated) echo "{\"demo\":{\"current\":\"1\",\"latest\":\"2\"}}"; exit 1;; install) exit 42;; list) echo "{\"dependencies\":{\"demo\":{\"version\":\"1\"}}}";; esac'
    run aggregate --provider npm
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
    ! grep -q 'npm:list' "$CALL_LOG"
}

@test "pip defaults outdated top-level and treats user as discovery scope only" {
    stub pip 'case "$1" in
        list) if [[ -f "$WORK/updated" ]]; then v=2; else v=1; fi
              printf "[{\"name\":\"My_Package\",\"version\":\"%s\",\"latest_version\":\"9\"}]\n" "$v";;
        install) touch "$WORK/updated";;
    esac'
    run aggregate --provider pip --options '{"pip":{"user":true}}'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].resultingVersion' "$WORK/results.json")" = 2 ]
    grep -q 'pip:list .*--user --not-required --outdated' "$CALL_LOG"
    grep -qx 'pip:install --upgrade My_Package' "$CALL_LOG"
    : > "$CALL_LOG"
    run aggregate --provider pip --dry-run --options '{"pip":{"topLevel":false}}'
    [ "$status" -eq 0 ]
    ! grep -q -- '--not-required' "$CALL_LOG"
}

@test "pip failed update remains failed and missing observed version is unknown" {
    stub pip 'case "$1" in list) echo "[{\"name\":\"demo\",\"version\":\"1\"}]";; install) exit 42;; esac'
    run aggregate --provider pip
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
    stub pip 'case "$1" in list) if [[ -f "$WORK/updated" ]]; then echo "[]"; else echo "[{\"name\":\"demo\",\"version\":\"1\"}]"; fi;; install) touch "$WORK/updated";; esac'
    run aggregate --provider pip
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
}

@test "dotnet previews installed global candidates with unknown proposed versions" {
    stub dotnet 'case "$1 $2" in
        "--list-sdks ") echo "8.0.100 [/sdk]";;
        "tool list") printf "Package Id      Version      Commands\n--------------------------------------\ndemo-tool      1.0.0        demo\nother      1.0.0        other\n";;
        *) exit 99;;
    esac'
    run aggregate --provider dotnet --dry-run --options '{"dotnet":{"name":"demo-*"}}'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].target' "$WORK/results.json")" = global-tool:demo-tool ]
    [ "$(jq -r '.[0].proposedVersion' "$WORK/results.json")" = null ]
    grep -qx 'dotnet:tool list -g' "$CALL_LOG"
    stub dotnet 'exit 0'
    run aggregate --provider dotnet
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Skipped ]
}

@test "dotnet updates only global tools and reports observed rather than proposed versions" {
    stub dotnet 'case "$1 $2" in
        "--list-sdks ") echo "8.0.100 [/sdk]";;
        "tool list") v=1.0; [[ ! -f "$WORK/updated" ]] || v=2.0
            printf "Package Id      Version      Commands\n--------------------------------------\ndemo      %s        demo\n" "$v";;
        "tool update") [[ "${FAIL_UPDATE:-0}" == 0 ]] || exit 42; touch "$WORK/updated";;
        *) exit 99;;
    esac'
    run aggregate --provider dotnet
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0] | [.status,.previousVersion,.resultingVersion] | join(",")' "$WORK/results.json")" = Updated,1.0,2.0 ]
    grep -qx 'dotnet:tool update demo -g' "$CALL_LOG"
    export FAIL_UPDATE=1
    run aggregate --provider dotnet --stop-on-failure
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
    ! grep -q -- '--local' "$CALL_LOG"
}

@test "uv tools-only stays lazy and preserves upgrade constraints" {
    stub uv 'case "$1 $2" in
        "tool list") if [[ -f "$WORK/updated" ]]; then echo "demo v2.0"; else echo "demo v1.0"; fi; echo "- demo";;
        "tool upgrade") touch "$WORK/updated";;
        *) exit 99;;
    esac'
    run aggregate --provider uv --options '{"uv":{"scope":"Tools"}}'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0] | [.target,.status,.resultingVersion] | join(",")' "$WORK/results.json")" = tool:demo,Updated,2.0 ]
    grep -qx 'uv:tool upgrade demo' "$CALL_LOG"
    ! grep -q 'uv:pip\|install' "$CALL_LOG"
}

@test "uv all scope separates identical package and tool names and observes unchanged" {
    stub uv 'case "$1 $2" in
        "pip list") echo "[{\"name\":\"demo\",\"version\":\"1.0\",\"latest_version\":\"2.0\"}]";;
        "pip show") echo "Required-by:";;
        "tool list") echo "demo v1.0"; echo "- demo";;
        "pip install"|"tool upgrade") exit 0;;
        *) exit 99;;
    esac'
    run aggregate --provider uv
    [ "$status" -eq 0 ]
    [ "$(jq -r 'map(.target) | join(",")' "$WORK/results.json")" = package:demo,tool:demo ]
    [ "$(jq -r 'map(.status) | join(",")' "$WORK/results.json")" = Unchanged,Unchanged ]
}

@test "VS Code returns one bulk result per default and named profile" {
    stub vscode-ext 'echo "Older unrelated helper cannot accept profiles" >&2; exit 99'
    stub code 'case "$1" in --list-extensions) echo pub.demo@1.0;; --update-extensions) exit 0;; *) exit 99;; esac'
    run aggregate --provider vscode --options '{"vscode":{"profiles":["Work","Work"]}}' --dry-run
    [ "$status" -eq 0 ]
    ! grep -q -- '--update-extensions' "$CALL_LOG"
    run aggregate --provider vscode --options '{"vscode":{"profiles":["Work"]}}'
    [ "$status" -eq 0 ]
    [ "$(jq length "$WORK/results.json")" -eq 2 ]
    [ "$(jq -r 'map(.status)|join(",")' "$WORK/results.json")" = Updated,Updated ]
    [ "$(jq -r '.[1].resultingVersion' "$WORK/results.json")" = null ]
    [ "$(jq -r '.[1].resultingInventory[0].fullId' "$WORK/results.json")" = pub.demo ]
    grep -qx 'code:--update-extensions --profile Work' "$CALL_LOG"
    ! grep -q '^vscode-ext:' "$CALL_LOG"
}

@test "VS Code failed native completion stops profiles only with fail-fast" {
    stub code 'case "$1" in --list-extensions) echo pub.demo@1.0;; --update-extensions) exit 42;; esac'
    run aggregate --provider vscode --options '{"vscode":{"profiles":["Work"]}}' --stop-on-failure
    [ "$status" -ne 0 ]
    [ "$(jq length "$WORK/results.json")" -eq 1 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
    [ "$(grep -c -- 'code:--update-extensions' "$CALL_LOG")" -eq 1 ]
}
