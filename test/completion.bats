#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$BATS_TEST_TMPDIR/completion"
    mkdir -p "$WORK/stubs" "$WORK/home"
    export REPO_ROOT WORK
    export HOME="$WORK/home" COPILOT_HOME="$WORK/home/copilot"
    export REAL_GIT="$(command -v git)"
    export REAL_NODE="$(command -v node)"
    export PATH="$WORK/stubs:$PATH"
    for native in copilot npm pip pip3 dotnet uv code perf curl fzf node az systemctl; do
        cat > "$WORK/stubs/$native" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$WORK/native.log"
exit 91
EOF
        chmod +x "$WORK/stubs/$native"
    done
}

complete_for() {
    local shell="$1"; shift
    if [[ "$shell" == bash ]]; then
        run bash -c '
            source "$REPO_ROOT/completions/bash/shm-git-completion.bash"
            [[ -z "${COMPLETION_CANONICAL_ROOT:-}" ]] || _SHM_COMPLETION_ROOT="$COMPLETION_CANONICAL_ROOT"
            COMP_WORDS=("$@"); COMP_CWORD="${COMPLETION_CWORD:-$((${#COMP_WORDS[@]} - 1))}"
            _shm_git_complete
            ((${#COMPREPLY[@]} == 0)) || printf "%s\n" "${COMPREPLY[@]}"
        ' -- "$@"
    else
        command -v zsh >/dev/null || skip 'zsh is not installed'
        run zsh -f -c '
            source "$REPO_ROOT/test/completion-zsh-env.zsh"
            compdef() { :; }
            source "$REPO_ROOT/completions/zsh/shm-git-completion.zsh"
            [[ -z "${COMPLETION_CANONICAL_ROOT:-}" ]] || _SHM_COMPLETION_ROOT="$COMPLETION_CANONICAL_ROOT"
            words=("$@"); CURRENT=$((${COMPLETION_CWORD:-$((${#words} - 1))} + 1))
            compadd() {
                while [[ "$1" != -- ]]; do shift; done
                shift
                local candidate
                for candidate in "$@"; do
                    case "$_shm_kind" in
                        available-branch|worktree-branch)
                            [[ "${candidate:l}" != *"${_shm_cur:l}"* ]] || print -r -- "$candidate" ;;
                        *) [[ "$candidate" != "$_shm_cur"* ]] || print -r -- "$candidate" ;;
                    esac
                done
            }
            _shm_zsh_context
        ' -- "$@"
    fi
    [ "$status" -eq 0 ]
}

has_candidate() { [[ $'\n'"$output"$'\n' == *$'\n'"$1"$'\n'* ]]; }
no_native_calls() { [ ! -e "$WORK/native.log" ]; }

git_fixture() {
    mkdir -p "$WORK/repo with space" "$WORK/caller"
    for repo in "$WORK/repo with space" "$WORK/caller"; do
        git -C "$repo" init -q --initial-branch=main
        git -C "$repo" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm seed
    done
    git -C "$WORK/repo with space" branch available
    git -C "$WORK/repo with space" branch busy
    git -C "$WORK/repo with space" worktree add -q "$WORK/linked with space" busy
    git -C "$WORK/caller" branch caller-only
    cd "$WORK/caller"
}

canonical_fixture() {
    export COMPLETION_CANONICAL_ROOT="$WORK/canonical" MOCK_SESSIONS='[{"id":"scoped-one"},{"id":"scoped-two"}]'
    mkdir -p "$COMPLETION_CANONICAL_ROOT/bin"
    cat > "$COMPLETION_CANONICAL_ROOT/bin/copilot-session" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >> "$WORK/discovery.argv"
printf '%s\n' "$PWD" > "$WORK/discovery.cwd"
[[ "$1" == list && "$2" == --json ]] || exit 91
printf '%s\n' "$MOCK_SESSIONS"
exit "${MOCK_DISCOVERY_STATUS:-0}"
EOF
    chmod +x "$COMPLETION_CANONICAL_ROOT/bin/copilot-session"
}

@test "Bash registers every public bin and returns only actually supported root flags" {
    run bash -c '
        source "$REPO_ROOT/completions/bash/shm-git-completion.bash"
        for file in "$REPO_ROOT"/bin/*; do
            cmd="${file##*/}"
            complete -p "$cmd" >/dev/null || exit 1
            COMP_WORDS=("$cmd" --); COMP_CWORD=1; _shm_git_complete
            case "$cmd" in
                in-location|is-elevated|reset-terminal) ((${#COMPREPLY[@]} == 0)) || exit 2 ;;
                *) [[ " ${COMPREPLY[*]} " == *" --help "* ]] || exit 3 ;;
            esac
        done
        printf "%s\n" covered
    '
    [ "$status" -eq 0 ]
    [ "$output" = covered ]
    no_native_calls
}

@test "Bash and zsh complete every operation family without invoking native commands" {
    for shell in bash zsh; do
        for contract in \
            'copilot-session:list select resume rename remove' \
            'copilot-session-maintenance:repair-events compress merge' \
            'copilot-mcp:list add remove' 'copilot-plugin:list install update uninstall' \
            'copilot-marketplace:list add remove browse' 'dev-setup:check apply' \
            'dotnet-tool:list install update uninstall' 'node-alias:set remove list' \
            'node-version:list current available install uninstall use' \
            'nvm-config:root version installed deactivate node-mirror npm-mirror' \
            'npm-package:list update' 'pip-package:list update' 'uv-package:list update' \
            'uv-tool:list install update' 'perf-record:start stop' \
            'vscode-ext:list install uninstall update'; do
            complete_for "$shell" "${contract%%:*}" ''
            [ "$output" = "$(printf '%s' "${contract#*:}" | tr ' ' '\n')" ]
        done
    done
    no_native_calls
}

@test "enumerated option values are identical in both shells" {
    for shell in bash zsh; do
        complete_for "$shell" package-update --provider ''
        [ "$output" = $'npm\npip\ndotnet\nuv\nvscode\npsresource' ]
        complete_for "$shell" package-update --exclude-provider uv
        [ "$output" = uv ]
        complete_for "$shell" dotnet-sdk-install --architecture ''
        [ "$output" = $'auto\namd64\nx64\nx86\narm64\narm\ns390x\nppc64le\nriscv64' ]
        complete_for "$shell" dotnet-sdk-install --quality ''
        [ "$output" = $'daily\npreview\nGA' ]
        complete_for "$shell" dotnet-sdk-install --channel ''
        [ "$output" = $'LTS\nSTS' ]
        complete_for "$shell" copilot-mcp add server --transport ''
        [ "$output" = $'stdio\nhttp\nsse' ]
        complete_for "$shell" copilot-mcp list --source ''
        [ "$output" = $'user\nworkspace\nplugin\nbuiltin' ]
        complete_for "$shell" installed-apps --source ''
        [ "$output" = $'dpkg\nrpm\nflatpak\nsnap' ]
        complete_for "$shell" pip-package list --state ''
        [ "$output" = $'any\noutdated\nuptodate' ]
        complete_for "$shell" git-config-set --scope ''
        [ "$output" = $'local\nglobal\nsystem' ]
        complete_for "$shell" git-worktree-new -k ''
        [ "$output" = $'user\nfeature\nrelease' ]
    done
    no_native_calls
}

@test "flags are operation-scoped and common flags are never invented" {
    for shell in bash zsh; do
        complete_for "$shell" copilot-mcp list --
        has_candidate --json
        ! has_candidate --dry-run
        ! has_candidate --transport
        complete_for "$shell" copilot-mcp add server --
        has_candidate --transport
        has_candidate --whatif
        ! has_candidate --json
        complete_for "$shell" dev-setup check --
        has_candidate --json
        ! has_candidate --force
        ! has_candidate --dry-run
        complete_for "$shell" dev-setup apply --
        has_candidate --force
        has_candidate --dry-run
        complete_for "$shell" node-version use --
        has_candidate --latest
        ! has_candidate --dry-run
        complete_for "$shell" dotnet-tool install --
        ! has_candidate --local
        ! has_candidate --dry-run
        complete_for "$shell" terminal-config --
        has_candidate --json
        ! has_candidate --dry-run
        complete_for "$shell" start-copilot --
        has_candidate --passthru
        ! has_candidate --json
        complete_for "$shell" copilot-launch-plan --
        has_candidate --json
        ! has_candidate --dry-run
        complete_for "$shell" git-worktree-remove --
        has_candidate --delete-branch=false
        complete_for "$shell" is-elevated --
        [ -z "$output" ]
    done
    no_native_calls
}

@test "free-text values consume flags literally rather than triggering completion or execution" {
    for shell in bash zsh; do
        complete_for "$shell" copilot-mcp add x --arg --
        [ -z "$output" ]
        complete_for "$shell" package-update --options --
        [ -z "$output" ]
        complete_for "$shell" start-copilot --name --dry-run --model
        [ "$output" = --model ]
        complete_for "$shell" git-worktree-new --user --kind --ki
        [ "$output" = --kind ]
        complete_for "$shell" git-worktree-prune --expire ''
        [ -z "$output" ]
        complete_for "$shell" git-config-set key --scope ''
        [ -z "$output" ]
        complete_for "$shell" start-copilot --selector '$(touch SHOULD_NOT_EXIST)' --model
        [ "$output" = --model ]
    done
    [ ! -e SHOULD_NOT_EXIST ]
    no_native_calls
}

@test "Bash paths preserve spaces, literal shell syntax, and directory/file distinctions" {
    cd "$WORK"
    mkdir -p 'folder name'
    printf '{}' > 'config file.json'
    printf '{}' > 'folder name/file one.json'
    printf '{}' > '$(touch SHOULD_NOT_EXIST)'
    printf '{}' > '--literal file'
    printf '{}' > "$HOME/personal file.json"
    complete_for bash dotnet-sdk-install --install-dir fol
    [ "$output" = 'folder name/' ]
    complete_for bash dev-setup apply 'config f'
    [ "$output" = 'config file.json' ]
    complete_for bash start-copilot --usage-output-file 'folder name/file'
    [ "$output" = 'folder name/file one.json' ]
    complete_for bash start-vscode '$('
    [ "$output" = '$(touch SHOULD_NOT_EXIST)' ]
    complete_for bash start-vscode -- --lit
    [ "$output" = '--literal file' ]
    complete_for bash in-location fol
    [ "$output" = 'folder name/' ]
    complete_for bash dotnet-sdk-install --install-dir 'config f'
    [ -z "$output" ]
    complete_for bash start-vscode '~/personal'
    [ "$output" = '~/personal file.json' ]
    [ ! -e SHOULD_NOT_EXIST ]
    no_native_calls
}

@test "terminators suppress wrapper flags and unknown-option arity never guesses" {
    for shell in bash zsh; do
        for command in start-copilot copilot-launch-plan; do
            complete_for "$shell" "$command" -- --model
            [ -z "$output" ]
        done
        complete_for "$shell" copilot-session select -- --selector
        [ -z "$output" ]
        complete_for "$shell" git-branch-switch --unknown whatever ''
        [ -z "$output" ]
    done
    no_native_calls
}

@test "Git discovery honors repository selectors and excludes checked-out branches only for add" {
    git_fixture
    for shell in bash zsh; do
        complete_for "$shell" git-worktree-add --path "$WORK/repo with space" ''
        [ "$output" = available ]
        complete_for "$shell" git-worktree-add -C "$WORK/repo with space" AIL
        [ "$output" = available ]
        complete_for "$shell" git-worktree-switch -C "$WORK/repo with space" ''
        has_candidate main
        has_candidate busy
        ! has_candidate caller-only
        complete_for "$shell" git-branch-switch --path "$WORK/repo with space" ''
        has_candidate main
        has_candidate busy
        has_candidate available
        ! has_candidate caller-only
        complete_for "$shell" git-branch-remove -C "$WORK/repo with space" ''
        has_candidate busy
    done
    [ "$(git -C "$WORK/repo with space" branch --format='%(refname:short)')" = $'available\nbusy\nmain' ]
    [ "$(git -C "$WORK/repo with space" worktree list --porcelain | grep -c '^worktree ')" -eq 2 ]
    no_native_calls
}

@test "Git repository failure has no cwd fallback or fabricated candidates" {
    git_fixture
    for shell in bash zsh; do
        for invalid in "$WORK/missing" '' '$(touch SHOULD_NOT_EXIST)'; do
            complete_for "$shell" git-worktree-add -C "$invalid" ''
            [ -z "$output" ]
        done
    done
    [ ! -e SHOULD_NOT_EXIST ]
    cat > "$WORK/stubs/git" <<'EOF'
#!/usr/bin/env bash
exit 92
EOF
    chmod +x "$WORK/stubs/git"
    for shell in bash zsh; do
        complete_for "$shell" git-worktree-switch -C "$WORK/repo with space" ''
        [ -z "$output" ]
        complete_for "$shell" git-worktree-add --ki
        [ -z "$output" ]
    done
    no_native_calls
}

@test "Git path-addressed worktrees and destination operands are not repository selectors" {
    git_fixture
    complete_for bash git-worktree-lock --path "$WORK/linked"
    [ "$output" = "$WORK/linked with space/" ]
    complete_for bash git-worktree-move -C "$WORK/repo with space" busy "$WORK/lin"
    [ "$output" = "$WORK/linked with space/" ]
    complete_for bash git-worktree-switch --path "$WORK/lin"
    [ "$output" = "$WORK/linked with space/" ]
    complete_for bash git-worktree-remove --path "$WORK/lin"
    [ "$output" = "$WORK/linked with space/" ]
    for shell in bash zsh; do
        complete_for "$shell" git-worktree-remove --path "$WORK/linked with space" -C "$WORK/repo with space" ''
        [ -z "$output" ]
        complete_for "$shell" git-worktree-switch -C "$WORK/repo with space" --path "$WORK/linked with space" ''
        [ -z "$output" ]
        complete_for "$shell" git-worktree-remove -C "$WORK/repo with space" --delete-branch false ''
        has_candidate busy
        ! has_candidate caller-only
    done
    no_native_calls
}

@test "Git restore paths use the explicit repository and work after a terminator" {
    git_fixture
    printf 'content\n' > "$WORK/repo with space/literal file"
    printf 'content\n' > "$WORK/repo with space/--literal file"
    complete_for bash git-restore -C "$WORK/repo with space" 'literal f'
    [ "$output" = 'literal file' ]
    complete_for bash git-restore -C "$WORK/repo with space" -- --lit
    [ "$output" = '--literal file' ]
    complete_for bash git-restore -C "$WORK/missing" ''
    [ -z "$output" ]
    no_native_calls
}

@test "cached branches, tags, remotes and stash selectors use read-only Git discovery" {
    git_fixture
    git -C "$WORK/repo with space" remote add upstream https://example.invalid/no-network.git
    git -C "$WORK/repo with space" update-ref refs/remotes/upstream/topic HEAD
    git -C "$WORK/repo with space" tag v1
    printf 'change\n' > "$WORK/repo with space/file"
    git -C "$WORK/repo with space" add file
    git -C "$WORK/repo with space" -c user.name=Test -c user.email=test@example.com stash push -qm test
    before="$(git -C "$WORK/repo with space" rev-parse refs/stash)"
    for shell in bash zsh; do
        complete_for "$shell" git-branch-switch -C "$WORK/repo with space" --track ''
        [ "$output" = upstream/topic ]
        complete_for "$shell" git-tag-list -C "$WORK/repo with space" --name ''
        [ "$output" = v1 ]
        complete_for "$shell" git-sync -C "$WORK/repo with space" ''
        [ "$output" = upstream ]
        complete_for "$shell" git-stash-restore -C "$WORK/repo with space" --stash ''
        [ "$output" = 'stash@{0}' ]
    done
    [ "$(git -C "$WORK/repo with space" rev-parse refs/stash)" = "$before" ]
    no_native_calls
}

@test "session completion calls only canonical list and forwards scope as literal argv" {
    canonical_fixture
    for shell in bash zsh; do
        rm -f "$WORK/discovery.argv"
        complete_for "$shell" copilot-session list --repository 'owner/repo' --branch 'topic' --summary --all --id sco
        [ "$output" = $'scoped-one\nscoped-two' ]
        run python3 -c '
import os
with open(os.environ["WORK"] + "/discovery.argv", "rb") as f:
    args = f.read().split(b"\0")[:-1]
assert args == [b"list", b"--json", b"--repository", b"owner/repo", b"--branch", b"topic", b"--summary", b"--all"], args
'
        [ "$status" -eq 0 ]
        rm -f "$WORK/discovery.argv"
        complete_for "$shell" copilot-session rename ''
        [ "$output" = $'scoped-one\nscoped-two' ]
        run python3 -c '
import os
with open(os.environ["WORK"] + "/discovery.argv", "rb") as f:
    assert f.read() == b"list\0--json\0"
'
        [ "$status" -eq 0 ]
    done
    no_native_calls
}

@test "global select completion honors its explicit scope without running the picker" {
    canonical_fixture
    for shell in bash zsh; do
        rm -f "$WORK/discovery.argv"
        complete_for "$shell" copilot-session select --selector '$(touch SHOULD_NOT_EXIST)' --branch main --id ''
        [ "$output" = $'scoped-one\nscoped-two' ]
        run python3 -c '
import os
with open(os.environ["WORK"] + "/discovery.argv", "rb") as f:
    assert f.read() == b"list\0--json\0--branch\0main\0--all\0"
'
        [ "$status" -eq 0 ]
    done
    [ ! -e SHOULD_NOT_EXIST ]
    no_native_calls
}

@test "launcher session IDs follow the literal change directory and do not fall back" {
    canonical_fixture
    mkdir -p "$WORK/session scope"
    for shell in bash zsh; do
        complete_for "$shell" start-copilot -C "$WORK/session scope" --resume-session ''
        [ "$output" = $'scoped-one\nscoped-two' ]
        [ "$(cat "$WORK/discovery.cwd")" = "$WORK/session scope" ]
        complete_for "$shell" start-copilot "--change-dir=$WORK/session scope" --resume-session ''
        [ "$output" = $'scoped-one\nscoped-two' ]
        [ "$(cat "$WORK/discovery.cwd")" = "$WORK/session scope" ]
        rm -f "$WORK/discovery.argv"
        complete_for "$shell" copilot-launch-plan --change-dir "$WORK/missing" --resume-session ''
        [ -z "$output" ]
        [ ! -e "$WORK/discovery.argv" ]
        complete_for "$shell" start-copilot -C '$(touch SHOULD_NOT_EXIST)' --resume-session ''
        [ -z "$output" ]
    done
    complete_for bash start-copilot --change-dir = "$WORK/session scope" --resume-session ''
    [ "$output" = $'scoped-one\nscoped-two' ]
    [ "$(cat "$WORK/discovery.cwd")" = "$WORK/session scope" ]
    [ ! -e SHOULD_NOT_EXIST ]
    no_native_calls
}

@test "maintenance completes only ID operands, not numbers or rename text" {
    canonical_fixture
    for shell in bash zsh; do
        complete_for "$shell" copilot-session-maintenance merge first ''
        [ "$output" = $'scoped-one\nscoped-two' ]
        complete_for "$shell" copilot-session-maintenance compress first --keep ''
        [ -z "$output" ]
        complete_for "$shell" copilot-session rename first ''
        [ -z "$output" ]
        complete_for "$shell" copilot-session resume first ''
        [ -z "$output" ]
    done
    no_native_calls
}

@test "failed or malformed canonical session discovery never leaks partial candidates" {
    canonical_fixture
    for shell in bash zsh; do
        export MOCK_DISCOVERY_STATUS=42
        complete_for "$shell" copilot-session resume ''
        [ -z "$output" ]
        unset MOCK_DISCOVERY_STATUS
        export MOCK_SESSIONS='[{"id":"partial"}] not-json'
        complete_for "$shell" copilot-session resume ''
        [ -z "$output" ]
        export MOCK_SESSIONS='[{"id":null},{"id":""},{"id":"bad\nline"}]'
        complete_for "$shell" copilot-session remove ''
        [ -z "$output" ]
    done
    no_native_calls
}

@test "completion does not load nvm initialization scripts or query remote catalogs" {
    export NVM_DIR="$WORK/nvm"
    mkdir -p "$NVM_DIR"
    printf 'touch "$WORK/MUTATED"\n' > "$NVM_DIR/nvm.sh"
    for shell in bash zsh; do
        complete_for "$shell" node-version install ''
        [ -z "$output" ]
        complete_for "$shell" node-version available ''
        [ -z "$output" ]
        complete_for "$shell" node-alias set name ''
        [ -z "$output" ]
        complete_for "$shell" npm-package update ''
        [ -z "$output" ]
        complete_for "$shell" copilot-plugin install ''
        [ -z "$output" ]
    done
    [ ! -e "$WORK/MUTATED" ]
    no_native_calls
}

@test "native launcher and MCP contracts expose new flags and exact enumerable values" {
    for shell in bash zsh; do
        complete_for "$shell" start-copilot --
        for flag in --prompt --interactive --fleet --auto-tier --dynamic-retrieval \
            --mouse --no-mouse --additional-mcp-config --mcp-github-auth \
            --fleet; do
            has_candidate "$flag"
        done
        ! has_candidate --prefer-version
        ! has_candidate --enable-reasoning-summaries
        ! has_candidate --retrieval-skills
        ! has_candidate --no-eager-powershell-resolution
        complete_for "$shell" start-copilot --auto-tier ''
        [ "$output" = $'efficiency\nbalance\nintelligence' ]
        complete_for "$shell" copilot-launch-plan --dynamic-retrieval ''
        [ "$output" = $'skills=on\nskills=off' ]
        complete_for "$shell" start-copilot --mouse ''
        [ "$output" = $'on\noff' ]
        complete_for "$shell" start-copilot --prompt --fleet --auto-tier ''
        [ "$output" = $'efficiency\nbalance\nintelligence' ]
        complete_for "$shell" start-copilot --model=auto --mouse ''
        [ "$output" = $'on\noff' ]
        complete_for "$shell" copilot-mcp add server --
        has_candidate --tools
        has_candidate --timeout
        complete_for "$shell" copilot-mcp add server --tools ''
        [ "$output" = '*' ]
        complete_for "$shell" copilot-mcp add server --timeout ''
        [ -z "$output" ]
        complete_for "$shell" copilot-plugin install --
        has_candidate --dry-run
    done
    no_native_calls
}

@test "Bash handles attached native values and readline equals word breaks" {
    complete_for bash start-copilot --auto-tier=in
    [ "$output" = --auto-tier=intelligence ]
    complete_for bash start-copilot --auto-tier = in
    [ "$output" = intelligence ]
    complete_for bash start-copilot --auto-tier =
    [ "$output" = $'efficiency\nbalance\nintelligence' ]
    complete_for bash start-copilot --dynamic-retrieval skills = of
    [ "$output" = off ]
    complete_for bash start-copilot --dynamic-retrieval skills=of
    [ "$output" = skills=off ]
    complete_for bash git-worktree-remove --delete-branch = f
    [ "$output" = false ]
    complete_for bash dotnet-sdk-install --architecture=x
    [ -z "$output" ]
    no_native_calls
}

@test "MCP config path completion keeps at-prefix and canonical home without evaluating JSON" {
    cd "$WORK"
    mkdir -p "$COPILOT_HOME"
    printf '{}' > "$COPILOT_HOME/mcp config.json"
    printf '{}' > 'local config.json'
    complete_for bash start-copilot --additional-mcp-config '@local'
    [ "$output" = '@local config.json' ]
    complete_for bash start-copilot --additional-mcp-config '@~/mcp'
    [ "$output" = '@~/mcp config.json' ]
    complete_for bash start-copilot '--additional-mcp-config=@local'
    [ "$output" = '--additional-mcp-config=@local config.json' ]
    complete_for bash start-copilot --additional-mcp-config = '@local'
    [ "$output" = '@local config.json' ]
    for shell in bash zsh; do
        complete_for "$shell" start-copilot --additional-mcp-config '{"command":"$(touch SHOULD_NOT_EXIST)"}' --mouse ''
        [ "$output" = $'on\noff' ]
    done
    [ ! -e SHOULD_NOT_EXIST ]
    no_native_calls
}

@test "complete Git and session scope selectors after the cursor remain authoritative" {
    git_fixture
    export COMPLETION_CWORD=1
    for shell in bash zsh; do
        complete_for "$shell" git-worktree-add '' -C "$WORK/repo with space"
        [ "$output" = available ]
        complete_for "$shell" git-branch-switch '' --path "$WORK/repo with space"
        has_candidate busy
        ! has_candidate caller-only
        complete_for "$shell" git-worktree-add '' -C "$WORK/missing"
        [ -z "$output" ]
    done
    canonical_fixture
    export COMPLETION_CWORD=3
    for shell in bash zsh; do
        rm -f "$WORK/discovery.argv"
        complete_for "$shell" copilot-session list --id '' --branch topic
        [ "$output" = $'scoped-one\nscoped-two' ]
        run python3 -c '
import os
with open(os.environ["WORK"] + "/discovery.argv", "rb") as f:
    assert f.read() == b"list\0--json\0--branch\0topic\0"
'
        [ "$status" -eq 0 ]
    done
    no_native_calls
}

@test "session results follow actual canonical list scope and leave recorded state unchanged" {
    mkdir -p "$WORK/project"
    local session="$COPILOT_HOME/session-state/11111111-1111-4111-8111-111111111111"
    mkdir -p "$session"
    printf 'id: 11111111-1111-4111-8111-111111111111\ncwd: %s\nname: Literal session\nupdated_at: 2026-10-01T00:00:00Z\n' "$WORK/project" > "$session/workspace.yaml"
    printf '{"type":"session.start"}\n' > "$session/events.jsonl"
    cd "$WORK/project"
    local before expected
    before="$(sha256sum "$session/workspace.yaml" "$session/events.jsonl")"
    expected="$("$REPO_ROOT/bin/copilot-session" list --json | jq -r '.[].id')"
    [ -n "$expected" ]
    for shell in bash zsh; do
        complete_for "$shell" copilot-session resume ''
        [ "$output" = "$expected" ]
    done
    [ "$(sha256sum "$session/workspace.yaml" "$session/events.jsonl")" = "$before" ]
    no_native_calls
}

@test "worktree identifiers come from canonical inventory rather than raw porcelain parsing" {
    git_fixture
    export COMPLETION_CANONICAL_ROOT="$WORK/canonical"
    mkdir -p "$COMPLETION_CANONICAL_ROOT/bin"
    cat > "$COMPLETION_CANONICAL_ROOT/bin/git-worktree-list" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -C && "$2" == "$WORK/repo with space" && "$3" == --json ]] || exit 91
printf '[{"branch":"paused-rebase-identity","detached":true}]\n'
EOF
    chmod +x "$COMPLETION_CANONICAL_ROOT/bin/git-worktree-list"
    for shell in bash zsh; do
        complete_for "$shell" git-worktree-switch -C "$WORK/repo with space" ''
        [ "$output" = paused-rebase-identity ]
    done
    no_native_calls
}

@test "selector executable completion reads PATH without running candidates or user shell functions" {
    printf '#!/usr/bin/env bash\ntouch "$WORK/MUTATED"\n' > "$WORK/stubs/safe-selector"
    chmod +x "$WORK/stubs/safe-selector"
    printf 'not executable\n' > "$WORK/stubs/safe-plain"
    for shell in bash zsh; do
        complete_for "$shell" start-copilot --selector safe-
        [ "$output" = safe-selector ]
    done
    complete_for bash start-copilot --selector "$WORK/stubs/safe-"
    [ "$output" = "$WORK/stubs/safe-selector" ]
    [ ! -e "$WORK/MUTATED" ]
    no_native_calls
}

session_scope_fixture() {
    local id="$1" repository="$2" branch="$3" cwd="$4"
    mkdir -p "$COPILOT_HOME/session-state/$id"
    printf 'name: %s\nrepository: %s\nbranch: %s\ncwd: %s\nupdated_at: 2026-10-01T00:00:00Z\n' \
        "$id" "$repository" "$branch" "$cwd" > "$COPILOT_HOME/session-state/$id/workspace.yaml"
}

@test "both shells complete moved GitHub sessions through canonical repository and branch scope" {
    mkdir -p "$WORK/moved-project" "$WORK/other"
    git -C "$WORK/moved-project" init -q -b main
    git -C "$WORK/moved-project" remote add origin https://github.com/owner/repo.git
    session_scope_fixture moved-one owner/repo main /old/worktree
    session_scope_fixture moved-two owner/repo main /another/old/worktree
    session_scope_fixture wrong-repository other/repo main "$WORK/moved-project"
    session_scope_fixture wrong-branch owner/repo topic "$WORK/moved-project"
    cd "$WORK/moved-project"
    local before
    before="$(sha256sum "$COPILOT_HOME"/session-state/*/workspace.yaml)"
    for shell in bash zsh; do
        complete_for "$shell" copilot-session resume moved-
        [ "$output" = $'moved-one\nmoved-two' ]
        complete_for "$shell" copilot-session list --branch topic --id ''
        [ -z "$output" ]
        complete_for "$shell" copilot-session list --all --branch topic --id ''
        [ "$output" = wrong-branch ]
        cd "$WORK/other"
        complete_for "$shell" start-copilot --change-dir ../moved-project --resume-session moved-
        [ "$output" = $'moved-one\nmoved-two' ]
        [ "$PWD" = "$WORK/other" ]
        cd "$WORK/moved-project"
    done
    [ "$(sha256sum "$COPILOT_HOME"/session-state/*/workspace.yaml)" = "$before" ]
    no_native_calls
}

@test "both shells use canonical Azure origin normalization without remote or picker calls" {
    # Node executes only the local canonical identity parser, not a CLI engine.
    ln -sf "$REAL_NODE" "$WORK/stubs/node"
    mkdir -p "$WORK/azure-project"
    git -C "$WORK/azure-project" init -q -b main
    git -C "$WORK/azure-project" remote add origin https://dev.azure.com/org/Project%20Name/_git/Repo%20Name.git
    session_scope_fixture azure-moved 'org/Project Name/Repo Name' main /old/worktree
    session_scope_fixture azure-conflict 'org/Other Project/Repo Name' main "$WORK/azure-project"
    session_scope_fixture azure-branch 'org/Project Name/Repo Name' topic "$WORK/azure-project"
    cd "$WORK/azure-project"
    for shell in bash zsh; do
        complete_for "$shell" copilot-session resume azure-
        [ "$output" = azure-moved ]
        complete_for "$shell" copilot-launch-plan --resume-session azure-
        [ "$output" = azure-moved ]
    done
    git remote set-url origin 'https://dev.azure.com/org/Project%2FName/_git/Repo%20Name'
    for shell in bash zsh; do
        complete_for "$shell" copilot-session resume azure-moved
        [ -z "$output" ]
    done
    no_native_calls
}
