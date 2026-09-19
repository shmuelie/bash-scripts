#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    export COPILOT_HOME="$WORK/home"
    export PATH="$REPO_ROOT/bin:$PATH"
    for id in first second; do
        local dir="$COPILOT_HOME/session-state/$id"
        mkdir -p "$dir"
        printf 'id: %s\ncwd: /synthetic/project\nupdated_at: 2026-01-01T00:00:00Z\nname: %s\n' \
            "$id" "$id" > "$dir/workspace.yaml"
        printf '{"type":"session.start","id":"%s","data":{"sessionId":"%s"}}\n' \
            "$id" "$id" > "$dir/events.jsonl"
    done
    A="$COPILOT_HOME/session-state/first"
    B="$COPILOT_HOME/session-state/second"
}

teardown() {
    rm -rf -- "$WORK"
}

assert_preserved() {
    [ -d "$A" ]
    [ -d "$B" ]
    [ "$(find "$COPILOT_HOME/session-state" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2 ]
}

@test "merge refuses differing artifacts before creating a destination or deleting sources" {
    for sub in files research rewind-snapshots/backups; do
        mkdir -p "$A/$sub" "$B/$sub"
        printf 'first\n' > "$A/$sub/same.txt"
        printf 'second\n' > "$B/$sub/same.txt"
        run copilot-session-maintenance merge first second --remove-source
        [ "$status" -ne 0 ]
        [[ "$output" == *"Conflicting merge artifact"* ]]
        assert_preserved
        [ "$(cat "$A/$sub/same.txt")" = first ]
        [ "$(cat "$B/$sub/same.txt")" = second ]
    done
}

@test "merge preserves identical overlaps hidden files and nested rewind backups" {
    mkdir -p "$A/files/shared" "$B/files/shared" "$A/rewind-snapshots/backups/nested"
    printf 'same\n' > "$A/files/shared/same.txt"
    cp "$A/files/shared/same.txt" "$B/files/shared/same.txt"
    printf 'hidden\n' > "$B/files/shared/.hidden"
    printf 'rewind\n' > "$A/rewind-snapshots/backups/nested/file"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -eq 0 ]
    local dest="$COPILOT_HOME/session-state/${lines[-1]}"
    [ "$(cat "$dest/files/shared/same.txt")" = same ]
    [ "$(cat "$dest/files/shared/.hidden")" = hidden ]
    [ "$(cat "$dest/rewind-snapshots/backups/nested/file")" = rewind ]
    [ ! -e "$A" ]
    [ ! -e "$B" ]
}

@test "merge rejects file-directory and incompatible case-only conflicts" {
    mkdir -p "$A/files" "$B/files/same"
    printf 'file\n' > "$A/files/same"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
    rmdir "$B/files/same"
    printf 'different\n' > "$B/files/SAME"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
}

@test "merge rejects dangling links linked directories and special files without following them" {
    mkdir -p "$A/files" "$WORK/outside"
    printf 'keep\n' > "$WORK/outside/sentinel"
    ln -s "$WORK/missing" "$A/files/broken"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
    unlink "$A/files/broken"
    ln -s "$WORK/outside" "$A/files/link"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
    [ "$(cat "$WORK/outside/sentinel")" = keep ]
    unlink "$A/files/link"
    mkfifo "$A/files/pipe"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
}

@test "merge preview skips artifact inspection and leaves sources alone" {
    mkdir -p "$A/files"
    ln -s "$WORK/missing" "$A/files/broken"
    run copilot-session-maintenance merge first second --remove-source --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"What if:"* ]]
    assert_preserved
}

@test "merge never removes an existing destination it does not own" {
    mkdir -p "$WORK/stub" "$COPILOT_HOME/session-state/existing"
    printf 'keep\n' > "$COPILOT_HOME/session-state/existing/sentinel"
    printf '#!/usr/bin/env bash\nprintf "existing\\n"\n' > "$WORK/stub/cat"
    chmod +x "$WORK/stub/cat"
    run env PATH="$WORK/stub:$PATH" copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [ -f "$COPILOT_HOME/session-state/existing/sentinel" ]
    [ -d "$A" ]
    [ -d "$B" ]
}
