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

checkpoint_index() {
    printf '# Checkpoint History\n\n| # | Title | File |\n|---|---|---|\n| 9 | %s | %s |\n' "$2" "$3" > "$1/checkpoints/index.md"
}

@test "merge preserves checkpoint titles references nested indexes and unindexed bodies" {
    mkdir -p "$A/checkpoints/nested" "$B/checkpoints"
    printf 'first\n' > "$A/checkpoints/first.md"
    printf 'second\n' > "$B/checkpoints/second.md"
    printf 'nested index\n' > "$A/checkpoints/nested/index.md"
    printf 'unindexed\n' > "$B/checkpoints/.unindexed"
    checkpoint_index "$A" 'First title' first.md
    checkpoint_index "$B" 'Second title' second.md
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -eq 0 ]
    local cp="$COPILOT_HOME/session-state/${lines[-1]}/checkpoints"
    [ "$(cat "$cp/first.md")" = first ]
    [ "$(cat "$cp/second.md")" = second ]
    [ "$(cat "$cp/nested/index.md")" = 'nested index' ]
    [ "$(cat "$cp/.unindexed")" = unindexed ]
    grep -Fxq '| 1 | First title | first.md |' "$cp/index.md"
    grep -Fxq '| 2 | Second title | second.md |' "$cp/index.md"
    [ ! -d "$A" ]
    [ ! -d "$B" ]
}

@test "checkpoint collisions include nested indexes but not the generated root index" {
    mkdir -p "$A/checkpoints/nested" "$B/checkpoints/nested"
    printf 'first\n' > "$A/checkpoints/nested/index.md"
    printf 'second\n' > "$B/checkpoints/nested/index.md"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [[ "$output" == *"Conflicting merge artifact"* ]]
    assert_preserved
}

@test "checkpoint parser rejects unsafe missing non-file and unsupported references" {
    mkdir -p "$A/checkpoints/directory"
    local reference
    for reference in '../events.jsonl' '/absolute' 'file:stream' './body.md' \
        'a//b.md' 'a/../b.md' 'body.' 'index.md' '[body](body.md)' \
        '`body.md`' '<body.md>' 'missing.md' directory; do
        checkpoint_index "$A" Title "$reference"
        run copilot-session-maintenance merge first second --remove-source
        [ "$status" -ne 0 ]
        assert_preserved
    done
}

@test "checkpoint parser rejects unsupported tables and linked indexes or bodies" {
    mkdir -p "$A/checkpoints"
    local content
    for content in '{"checkpoints":[]}' '| # | File |' '| 1 | Title | body.md | extra |'; do
        printf '%s\n' "$content" > "$A/checkpoints/index.md"
        run copilot-session-maintenance merge first second --remove-source
        [ "$status" -ne 0 ]
        [[ "$output" == *"Unsupported checkpoint index"* ]]
        assert_preserved
    done
    rm "$A/checkpoints/index.md"
    ln -s "$WORK/missing" "$A/checkpoints/index.md"
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
    unlink "$A/checkpoints/index.md"
    printf 'outside\n' > "$WORK/body.md"
    ln -s "$WORK/body.md" "$A/checkpoints/body.md"
    checkpoint_index "$A" Title body.md
    run copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    assert_preserved
    [ "$(cat "$WORK/body.md")" = outside ]
}

@test "checkpoint read-back detects corrupted copied bodies before source removal" {
    mkdir -p "$A/checkpoints"
    printf 'original\n' > "$A/checkpoints/body.md"
    checkpoint_index "$A" Title body.md
    cat > "$WORK/corrupt.js" <<'EOF'
const fs = require('fs');
const copy = fs.copyFileSync;
fs.copyFileSync = function(src, dest, flags) {
    copy(src, dest, flags);
    if (dest.endsWith('/checkpoints/body.md')) fs.writeFileSync(dest, 'corrupt');
};
EOF
    run env NODE_OPTIONS="--require=$WORK/corrupt.js" copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [[ "$output" == *"verification failed"* ]]
    assert_preserved
    [ "$(cat "$A/checkpoints/body.md")" = original ]
}

@test "checkpoint read-back detects a corrupted generated index" {
    cat > "$WORK/corrupt.js" <<'EOF'
const fs = require('fs');
const write = fs.writeFileSync;
fs.writeFileSync = function(file, data, options) {
    write(file, file.endsWith('/checkpoints/index.md') ? 'corrupt' : data, options);
};
EOF
    run env NODE_OPTIONS="--require=$WORK/corrupt.js" copilot-session-maintenance merge first second --remove-source
    [ "$status" -ne 0 ]
    [[ "$output" == *"index failed read-back verification"* ]]
    assert_preserved
}
