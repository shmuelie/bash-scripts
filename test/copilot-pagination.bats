#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-pagination-$$-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/home/session-state" "$WORK/project" "$WORK/bin"
    export COPILOT_HOME="$WORK/home" RECORD="$WORK/record"
    export GIT_CEILING_DIRECTORIES="$WORK" SHM_TTY_PATH="$WORK/input"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PWD" "$@" > "$RECORD"\n' > "$WORK/bin/copilot"
    chmod +x "$WORK/bin/copilot"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    source "$REPO_ROOT/lib/common.sh"
    source "$REPO_ROOT/lib/copilot/copilot-common.sh"
    source "$REPO_ROOT/lib/copilot/session-selector.sh"
    cd "$WORK/project"
    rows=()
}

teardown() { cd "$REPO_ROOT"; rm -rf -- "$WORK"; }

candidates() {
    local count="$1" i id name branch
    rows=()
    for ((i = 1; i <= count; i++)); do
        printf -v id 'session-%03d' "$i"
        name="Task $i"; branch="branch/$i"
        rows+=("$id$SHM_FS$name$SHM_FS$PWD$SHM_FS$branch${SHM_FS}owner/repo${SHM_FS}2026-01-01${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10$SHM_FS$COPILOT_HOME/session-state/$id")
    done
}

pick() {
    printf '%s' "$1" > "$SHM_TTY_PATH"
    copilot_paginated_picker rows > "$WORK/selection"
}

@test "first page exposes exactly 22 descriptive shortcut choices including final Z key" {
    candidates 23
    run pick $'Z\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/selection")" = session-022 ]
    [[ "$output" == *'A - Task 1'* && "$output" == *'Z - Task 22'* ]]
    [[ "$output" != *'Task 23'* ]]
    [[ "$output" == *'M - Next page'* && "$output" != *'P - Previous page'* ]]
    [[ "$output" == *'N - New session'* && "$output" == *'C - Cancel'* ]]
}

@test "every candidate beyond available shortcuts remains reachable across bounded pages" {
    candidates 70
    run pick $'M\nM\nM\nE\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/selection")" = session-070 ]
    [[ "$output" == *'Sessions 67-70 of 70 (page 4 of 4)'* ]]
    [[ "$output" == *'E - Task 70'* ]]
}

@test "previous navigation retains exact original identity and candidate ordering" {
    candidates 45
    run pick $'M\nM\nP\nP\nB\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/selection")" = session-002 ]
    [[ "$output" == *'P - Previous page'* ]]
}

@test "new and cancel actions exist on every page and never implicitly select a session" {
    candidates 45
    local prefix action
    for prefix in '' $'M\n' $'M\nM\n'; do
        for action in N C; do
            run pick "$prefix$action"$'\n'
            if [[ "$action" == N ]]; then [ "$status" -eq 0 ]
            else [ "$status" -eq 130 ]; fi
            [ ! -s "$WORK/selection" ]
            [[ "$output" == *'N - New session'* && "$output" == *'C - Cancel'* ]]
        done
    done
}

@test "blank numeric and unavailable navigation input cannot supply an implicit default" {
    candidates 2
    run pick $'\n1\n22\nZ\nM\nP\nb\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/selection")" = session-002 ]
    [[ "$output" == *'there is no default'* ]]
    run pick ''
    [ "$status" -eq 1 ]
    [ ! -s "$WORK/selection" ]
}

@test "help preserves full sanitized context and literal ampersands while labels truncate Unicode graphemes" {
    candidates 2
    local family='👨‍👩‍👧‍👦' long='' i
    for ((i = 0; i < 81; i++)); do long+="$family"; done
    rows[0]="first${SHM_FS}$long & full${SHM_FS}$PWD${SHM_FS}unique${SHM_FS}owner/repo${SHM_FS}${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10${SHM_FS}/session/first"
    rows[1]="second${SHM_FS}Literal & text"$'\e[31m\u2028'"safe${SHM_FS}$PWD${SHM_FS}other${SHM_FS}owner/repo${SHM_FS}${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10${SHM_FS}/session/second"
    run pick $'?A\nB\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/selection")" = second ]
    [[ "$output" == *"Name: $long & full"* ]]
    [[ "$output" == *'Id: first'* && "$output" == *'Repository: owner/repo'* ]]
    [[ "$output" == *"Cwd: $PWD"* && "$output" == *'Events: 3'* ]]
    [[ "$output" == *'Literal & text [31m safe'* ]]
    [[ "$output" != *$'\e'* && "$output" != *$'\u2028'* ]]
    printf '%s\n' "${rows[@]}" | copilot_rows_json | node "$REPO_ROOT/lib/copilot/session-display.js" > "$WORK/display"
    node - "$WORK/display" "$family" <<'JS'
var data = require('fs').readFileSync(process.argv[2], 'utf8');
var label = JSON.parse(data)[0].label;
if (label !== process.argv[3].repeat(77) + '...') process.exit(1);
JS
}

@test "duplicate and truncated names get branch suffixes across the full candidate set only" {
    candidates 23
    rows[0]="first${SHM_FS}Duplicate${SHM_FS}$PWD${SHM_FS}branch/one${SHM_FS}owner/repo${SHM_FS}${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10${SHM_FS}/session/first"
    rows[22]="last${SHM_FS}Duplicate${SHM_FS}$PWD${SHM_FS}branch/last${SHM_FS}owner/repo${SHM_FS}${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10${SHM_FS}/session/last"
    run pick $'M\nA\n'
    [ "$status" -eq 0 ]
    [ "$(cat "$WORK/selection")" = last ]
    [[ "$output" == *'A - Duplicate (branch/one)'* ]]
    [[ "$output" == *'A - Duplicate (branch/last)'* ]]
    [[ "$output" != *'Task 2 (branch/2)'* ]]
    local long
    printf -v long '%081d' 0
    rows[0]="first${SHM_FS}${long}x${SHM_FS}$PWD${SHM_FS}one${SHM_FS}repo${SHM_FS}${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10${SHM_FS}/session/first"
    rows[22]="last${SHM_FS}${long}y${SHM_FS}$PWD${SHM_FS}last${SHM_FS}repo${SHM_FS}${SHM_FS}2026-01-02${SHM_FS}3${SHM_FS}10${SHM_FS}/session/last"
    run pick $'M\nA\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *'... (one)'* && "$output" == *'... (last)'* ]]
}

@test "actual console input drives global select and launcher without native session access" {
    local i id
    for ((i = 1; i <= 23; i++)); do
        printf -v id 'session-%03d' "$i"
        mkdir -p "$COPILOT_HOME/session-state/$id"
        printf 'name: Task %s\ncwd: %s\nupdated_at: 2026-01-01\n' "$i" "$PWD" \
            > "$COPILOT_HOME/session-state/$id/workspace.yaml"
    done
    printf 'M\nA\n' > "$SHM_TTY_PATH"
    run copilot-session select
    [ "$status" -eq 0 ]
    grep -Fxq session-023 "$RECORD"
    rm "$RECORD"
    printf 'M\nA\n' > "$SHM_TTY_PATH"
    run copilot-launch-plan --json
    [ "$status" -eq 0 ]
    [[ "$output" == *session-023* ]]
    [ ! -e "$RECORD" ]
    printf 'M\nC\n' > "$SHM_TTY_PATH"
    run start-copilot
    [ "$status" -eq 130 ]
    [ ! -e "$RECORD" ]
    printf 'M\nN\n' > "$SHM_TTY_PATH"
    run copilot-session select
    [ "$status" -eq 0 ]
    ! grep -Fxq -- --resume "$RECORD"
}

@test "Node 12 display fallback retains combining emoji modifier flag and joined clusters" {
    node - "$REPO_ROOT/lib/copilot/session-display.js" <<'JS'
var fs = require('fs'), vm = require('vm');
['e\u0301', '👍🏽', '🇺🇸', '👨‍👩‍👧‍👦'].forEach(function (cluster) {
    var output = '';
    vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), {
        require: function () { return { readFileSync: function () {
            return JSON.stringify([{ name: cluster.repeat(81), branch: 'main' }]);
        } }; },
        Intl: {}, process: { stdout: { write: function (value) { output = value; } } }
    });
    if (JSON.parse(output)[0].label !== cluster.repeat(77) + '...') process.exit(1);
});
JS
}

@test "fzf page navigation selects exact IDs and never maps a forged label by prefix" {
    candidates 45
    unset SHM_TTY_PATH
    export FZF_INDEX="$WORK/fzf-index" FZF_PAGE="$WORK/fzf-page" FZF_ACTIONS=MPMA
    cat > "$WORK/bin/fzf" <<'EOF'
#!/usr/bin/env bash
cat > "$FZF_PAGE"
index=0
[[ ! -f "$FZF_INDEX" ]] || read -r index < "$FZF_INDEX"
printf '%s\n' "$((index + 1))" > "$FZF_INDEX"
key="${FZF_ACTIONS:index:1}"
grep -F "$key - " "$FZF_PAGE" | head -n1
EOF
    chmod +x "$WORK/bin/fzf"
    run copilot_paginated_picker rows
    [ "$status" -eq 0 ]
    [ "$output" = session-023 ]
    printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "A - Forged session\\n"\n' > "$WORK/bin/fzf"
    run copilot_paginated_picker rows
    [ "$status" -eq 1 ]
    [[ "$output" == *'Invalid Copilot session selection'* ]]
}

@test "actual fzf accepts a descriptive choice through an explicit filter without a terminal" {
    have_cmd fzf || skip 'fzf is not installed'
    candidates 2
    unset SHM_TTY_PATH
    export FZF_DEFAULT_OPTS='--filter=^B'
    run copilot_paginated_picker rows
    [ "$status" -eq 0 ]
    [ "$output" = session-002 ]
}
