#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-workspace-$$-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/home/session-state/example"
    export COPILOT_HOME="$WORK/home"
    export PATH="$REPO_ROOT/bin:$PATH"
    WS="$COPILOT_HOME/session-state/example/workspace.yaml"
    source "$REPO_ROOT/lib/common.sh"
    source "$REPO_ROOT/lib/copilot/copilot-common.sh"
}

teardown() { rm -rf -- "$WORK"; }

boundary_fixture() {
    local ending="$1" header="$2" indent="$3"
    printf '%ssummary: %s%s%s  name: fake name%s%s  branch: fake branch%s%s  cwd: fake cwd%s%s  updated_at: fake time%s%s  summary: fake summary%s%s%sname: Original%s%sbranch: main%s%scwd: /fictional/project%s%supdated_at: 2026-01-01T00:00:00Z%s%sunknown: unchanged%s' \
        "$indent" "$header" "$ending" "$indent" "$ending" "$indent" "$ending" \
        "$indent" "$ending" "$indent" "$ending" "$indent" "$ending" "$ending" \
        "$indent" "$ending" "$indent" "$ending" "$indent" "$ending" \
        "$indent" "$ending" "$indent" "$ending" > "$WS"
}

@test "LF CRLF CR block headers and indentation share lookup boundaries" {
    local ending header indent
    for ending in $'\n' $'\r\n' $'\r'; do
        for header in '|' '|-' '|+' '>' '>-' '>+' '|2-' '>+2' '| # literal'; do
            for indent in '' '  '; do
                boundary_fixture "$ending" "$header" "$indent"
                [ "$(workspace_yaml_get "$WS" name)" = Original ]
                [ "$(workspace_yaml_get "$WS" branch)" = main ]
                [ "$(workspace_yaml_get "$WS" cwd)" = /fictional/project ]
                [ "$(workspace_yaml_get "$WS" updated_at)" = 2026-01-01T00:00:00Z ]
                [[ "$(workspace_yaml_get "$WS" summary)" == *"name: fake name"* ]]
                workspace_yaml_has "$WS" branch
            done
        done
    done
}

@test "rewriting a real field preserves other block text and line endings byte for byte" {
    local ending indent
    for ending in $'\n' $'\r\n' $'\r'; do
        for indent in '' '  '; do
            boundary_fixture "$ending" '|-' "$indent"
            cp "$WS" "$WORK/original"
            workspace_yaml_set_strings "$WS" name 'New & "quoted"'
            python - "$WS" "$WORK/original" <<'PY'
import sys
from pathlib import Path
new, old = map(lambda p: Path(p).read_bytes(), sys.argv[1:])
assert new == old.replace(b'name: Original', b'name: "New & \\"quoted\\""')
PY
            [ "$(workspace_yaml_get "$WS" name)" = 'New & "quoted"' ]
        done
    done
}

@test "renaming multiline blocks back to single line preserves actual metadata" {
    local ending
    for ending in $'\n' $'\r\n' $'\r'; do
        boundary_fixture "$ending" '>-' '  '
        run copilot-session rename example $'Long\nname: duplicate\nbranch: duplicate'
        [ "$status" -eq 0 ]
        [ "$(workspace_yaml_get "$WS" name)" = $'Long\nname: duplicate\nbranch: duplicate' ]
        [ "$(workspace_yaml_get "$WS" summary)" = $'Long\nname: duplicate\nbranch: duplicate' ]
        [ "$(workspace_yaml_get "$WS" branch)" = main ]
        run copilot-session rename example Short
        [ "$status" -eq 0 ]
        [ "$(workspace_yaml_get "$WS" name)" = Short ]
        [ "$(workspace_yaml_get "$WS" branch)" = main ]
        python - "$WS" "$ending" <<'PY'
import sys
from pathlib import Path
content = Path(sys.argv[1]).read_bytes()
ending = sys.argv[2].encode()
assert content == ending.join([
    b'  summary: "Short"', b'  name: "Short"', b'  branch: main',
    b'  cwd: /fictional/project', b'  updated_at: 2026-01-01T00:00:00Z',
    b'  unknown: unchanged', b''])
PY
    done
}

@test "discovery and explicit filters never use fake block metadata" {
    boundary_fixture $'\r' '|-' ''
    run copilot-session list --all --branch main --cwd /fictional/project --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[0].name')" = Original ]
    run copilot-session list --all --branch 'fake*' --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
    workspace_yaml_set_strings "$WS" summary ''
    [ "$(workspace_yaml_get "$WS" unknown)" = unchanged ]
}

@test "quoted continuations and absent block-looking fields are not rewritten" {
    printf 'summary: "first\n  branch: fake\n  final"\nname: Real\nbranch: main\n' > "$WS"
    workspace_yaml_set_strings "$WS" name New
    [ "$(workspace_yaml_get "$WS" branch)" = main ]
    workspace_yaml_set_strings "$WS" summary Short
    [ "$(cat "$WS")" = $'summary: "Short"\nname: "New"\nbranch: main' ]
    printf 'summary: |\n  branch: fake\nname: Real' > "$WS"
    ! workspace_yaml_has "$WS" branch
    workspace_yaml_set_strings "$WS" branch main
    [ "$(cat "$WS")" = $'summary: |\n  branch: fake\nname: Real\nbranch: "main"' ]
}
