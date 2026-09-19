#!/usr/bin/env bats

setup() {
    command -v pwsh >/dev/null || skip 'PowerShell required for canonical bridge fixture tests.'
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export WORK CALL_LOG="$WORK/calls" RESOURCE_FIXTURE="$WORK/fixture.json" RESOURCE_UPDATED="$WORK/updated"
    export PSModulePath="$REPO_ROOT/test/fixtures/packages/modules${PSModulePath:+:$PSModulePath}"
    unset RESOURCE_FAIL RESOURCE_WARN
    mkdir -p "$WORK/modules/Demo/1.0.0"
    : > "$CALL_LOG"
    export PATH="$REPO_ROOT/bin:$PATH"
    OPTIONS="$(jq -cn --arg root "$WORK/modules" '{psresource:{roots:[$root]}}')"
}

teardown() { [[ -z "${WORK:-}" ]] || rm -rf "$WORK"; }

aggregate() {
    local result=0
    package-update --provider psresource --options "$OPTIONS" --json "$@" > "$WORK/results.json" 2> "$WORK/errors" || result=$?
    if [[ "$result" != 0 ]]; then cat "$WORK/errors" "$WORK/results.json"; fi
    return "$result"
}

@test "resource consumer preserves prerelease labels for numeric roots and canonical metadata variants" {
    # These are canonical responses, not a second implementation of XML/manifest parsing.
    for origin in missing-xml unreadable-xml incomplete-xml recovered-xml-precedence; do
        jq -cn --arg origin "$origin" '{origin:$origin,before:"1.0.0-beta.2",after:"1.0.0-beta.10",comparison:1,repository:"RecordedFeed"}' > "$RESOURCE_FIXTURE"
        rm -f "$RESOURCE_UPDATED"
        run aggregate --dry-run
        [ "$status" -eq 0 ]
        [ "$(jq -r '.[0].previousVersion' "$WORK/results.json")" = 1.0.0-beta.2 ]
        [ "$(jq -r '.[0].proposedVersion' "$WORK/results.json")" = null ]
        [ ! -e "$RESOURCE_UPDATED" ]
        run aggregate
        [ "$status" -eq 0 ]
        [ "$(jq -r '.[0] | [.previousVersion,.resultingVersion,.status] | join(",")' "$WORK/results.json")" = 1.0.0-beta.2,1.0.0-beta.10,Updated ]
        grep -q 'compare:1.0.0-beta.2:1.0.0-beta.10' "$CALL_LOG"
    done
}

@test "resource stable promotion uses canonical comparison and repository override is explicit" {
    echo '{"before":"1.0.0-rc.1","after":"1.0.0","comparison":1,"repository":"RecordedFeed"}' > "$RESOURCE_FIXTURE"
    run aggregate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Updated ]
    grep -qx "update:$WORK/modules|Demo|" "$CALL_LOG"
    rm -f "$RESOURCE_UPDATED"
    OPTIONS="$(jq '.psresource.repository = "ExplicitFeed"' <<< "$OPTIONS")"
    run aggregate
    [ "$status" -eq 0 ]
    grep -qx "update:$WORK/modules|Demo|ExplicitFeed" "$CALL_LOG"
}

@test "resource roots and name exclusions are explicit and unavailable roots skip" {
    echo '{"before":"1.0.0-beta","after":"1.0.0-beta","comparison":0}' > "$RESOURCE_FIXTURE"
    OPTIONS="$(jq --arg root "$WORK/missing" '.psresource.roots += [$root] | .psresource.exclude=["Demo"]' <<< "$OPTIONS")"
    run aggregate --dry-run
    [ "$status" -eq 0 ]
    [ "$(jq length "$WORK/results.json")" -eq 1 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Skipped ]
    [ ! -e "$RESOURCE_UPDATED" ]
    ! grep -q "^discover:$HOME" "$CALL_LOG"
}

@test "resource warnings skips failures and decreasing versions remain honest" {
    echo '{"before":"1.0.0-beta","after":"1.0.0-beta","comparison":0}' > "$RESOURCE_FIXTURE"
    export RESOURCE_WARN=1
    run aggregate
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Skipped ]
    grep -q 'canonical repository warning' "$WORK/errors"
    export RESOURCE_FAIL=1
    run aggregate
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
    unset RESOURCE_FAIL RESOURCE_WARN
    rm -f "$RESOURCE_UPDATED"
    echo '{"before":"2.0.0","after":"1.0.0","comparison":-1}' > "$RESOURCE_FIXTURE"
    run aggregate
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' "$WORK/results.json")" = Failed ]
}
