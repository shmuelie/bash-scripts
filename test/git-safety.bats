#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    WORK="$(mktemp -d)"
    export WORK
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
    REAL_GIT="$(command -v git)"
    REAL_MV="$(command -v mv)"
    export REAL_GIT REAL_MV
    git init -q -b main "$WORK/seed"
    printf 'initial\n' > "$WORK/seed/file"
    git -C "$WORK/seed" add .
    git -C "$WORK/seed" commit -qm initial
    git clone -q --bare "$WORK/seed" "$WORK/upstream.git"
    git clone -q "$WORK/upstream.git" "$WORK/repo"
}

teardown() {
    rm -rf "$WORK"
}

advance_upstream() {
    printf 'new upstream content\n' > "$WORK/seed/added"
    git -C "$WORK/seed" add .
    git -C "$WORK/seed" commit -qm advance
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
}

save_prior_stash() {
    printf 'prior saved work\n' > "$WORK/repo/prior"
    git -C "$WORK/repo" stash push -qu -m prior
    PRIOR="$(git -C "$WORK/repo" rev-parse refs/stash)"
}

@test "status counts working index and double type changes and formats each" {
    rm "$WORK/repo/file"
    ln -s destination "$WORK/repo/file"
    run git-status-summary -C "$WORK/repo" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.indexModified,.workingModified,.hasChanges]|@tsv' <<< "$output")" = $'0\t1\ttrue' ]
    run git-status-segment --no-color "$WORK/repo"
    [[ "$output" == *'~1'* ]]

    git -C "$WORK/repo" add file
    run git-status-summary -C "$WORK/repo" --json
    [ "$(jq -r '[.indexModified,.workingModified,.hasChanges]|@tsv' <<< "$output")" = $'1\t0\ttrue' ]
    rm "$WORK/repo/file"
    printf 'initial\n' > "$WORK/repo/file"
    run git-status-summary -C "$WORK/repo" --json
    [ "$(jq -r '[.indexModified,.workingModified,.hasChanges]|@tsv' <<< "$output")" = $'1\t1\ttrue' ]
    run git-status-summary -C "$WORK/repo" --string
    [[ "$output" == *'~1'* ]]
    run git-status-segment --no-color "$WORK/repo"
    [[ "$output" == *'~1'*'~1'* ]]
}

@test "layout repair leaves occupied directories files repos and dangling links unchanged" {
    for kind in directory file repository symlink; do
        base="$WORK/$kind/acme/widget"
        mkdir -p "$base"
        git clone -q "$WORK/upstream.git" "$base/wrong"
        case "$kind" in
            directory) mkdir "$base/main"; printf sentinel > "$base/main/sentinel" ;;
            file) printf sentinel > "$base/main" ;;
            repository) git clone -q "$WORK/upstream.git" "$base/main" ;;
            symlink) ln -s missing "$base/main" ;;
        esac
        run git-repo-repair --root "$WORK/$kind" --json
        [ "$status" -eq 0 ]
        [ "$(jq -r '.[]|select(.from|endswith("/wrong"))|.status' <<< "$output")" = Skipped-DestinationExists ]
        [ -d "$base/wrong/.git" ]
        [ ! -e "$base/main/wrong" ]
        case "$kind" in
            directory) [ "$(cat "$base/main/sentinel")" = sentinel ] ;;
            file) [ "$(cat "$base/main")" = sentinel ] ;;
            repository) [ -d "$base/main/.git" ] ;;
            symlink) [ "$(readlink "$base/main")" = missing ] ;;
        esac
    done
}

@test "layout repair rejects a destination created after the guard without nesting" {
    base="$WORK/repos/acme/widget"
    mkdir -p "$base" "$WORK/stub"
    git clone -q "$WORK/upstream.git" "$base/wrong"
    export RACE_TARGET="$base/main"
    cat > "$WORK/stub/mv" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do destination="$arg"; done
if [[ "$destination" == "$RACE_TARGET" ]]; then
    mkdir "$RACE_TARGET"
    printf sentinel > "$RACE_TARGET/sentinel"
fi
exec "$REAL_MV" "$@"
EOF
    chmod +x "$WORK/stub/mv"
    run bash -c 'PATH="$1:$PATH" git-repo-repair --root "$2" --json 2>"$3"' \
        -- "$WORK/stub" "$WORK/repos" "$WORK/errors"
    [ "$(jq -r '.[0].status' <<< "$output")" = Error ]
    [ -d "$base/wrong/.git" ]
    [ ! -e "$base/main/wrong" ]
    [ "$(cat "$base/main/sentinel")" = sentinel ]
    grep -q 'exact destination' "$WORK/errors"
}

@test "layout conversion skips an occupied branch subdirectory before staging" {
    base="$WORK/repos/acme/widget"
    mkdir -p "$(dirname "$base")"
    git clone -q "$WORK/upstream.git" "$base"
    mkdir "$base/main"
    printf sentinel > "$base/main/sentinel"
    run git-repo-repair --root "$WORK/repos" --json
    [ "$(jq -r '.[0].status' <<< "$output")" = Skipped-DestinationExists ]
    [ -d "$base/.git" ]
    [ "$(cat "$base/main/sentinel")" = sentinel ]
}

@test "updater restores only its own stash and preserves older entries" {
    save_prior_stash
    printf 'working changes\n' > "$WORK/repo/file"
    advance_upstream
    run git-worktree-update -C "$WORK/repo" --json --no-github-account-resolve
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0]|[.status,.stashed]|@tsv' <<< "$output")" = $'Updated\ttrue' ]
    [ "$(git -C "$WORK/repo" rev-parse refs/stash)" = "$PRIOR" ]
    [ "$(cat "$WORK/repo/file")" = 'working changes' ]
    [ ! -e "$WORK/repo/prior" ]
}

@test "no-op stash for submodule dirt cannot pop an older unrelated stash or merge" {
    git -C "$WORK/seed" -c protocol.file.allow=always submodule add -q "$WORK/repo" sub
    git -C "$WORK/seed" commit -qm submodule
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    git -C "$WORK/repo" pull -q --ff-only
    git -C "$WORK/repo" -c protocol.file.allow=always submodule update --init --quiet
    save_prior_stash
    before="$(git -C "$WORK/repo" rev-parse HEAD)"
    printf 'submodule dirt\n' > "$WORK/repo/sub/file"
    advance_upstream
    run bash -c 'git-worktree-update -C "$1" --json --no-github-account-resolve 2>"$2"' \
        -- "$WORK/repo" "$WORK/errors"
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0]|[.status,.stashed]|@tsv' <<< "$output")" = $'StashFailed\tfalse' ]
    [ "$(git -C "$WORK/repo" rev-parse refs/stash)" = "$PRIOR" ]
    [ "$(git -C "$WORK/repo" rev-parse HEAD)" = "$before" ]
    [ ! -e "$WORK/repo/prior" ]
    grep -q 'No new stash' "$WORK/errors"
}

@test "stash restore conflicts are failures and retain the saved entry" {
    printf 'local edit\n' > "$WORK/repo/file"
    printf 'upstream edit\n' > "$WORK/seed/file"
    advance_upstream
    run bash -c 'git-worktree-update -C "$1" --json --no-github-account-resolve 2>"$2"' \
        -- "$WORK/repo" "$WORK/errors"
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' <<< "$output")" = StashFailed ]
    [ "$(git -C "$WORK/repo" stash list | wc -l)" -eq 1 ]
    grep -q 'stash retained' "$WORK/errors"
}

@test "ownership changes after merge retain both entries and restore exact saved changes" {
    printf 'local edit\n' > "$WORK/repo/file"
    advance_upstream
    mkdir "$WORK/stub"
    cat > "$WORK/stub/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$3" == merge ]]; then
    "$REAL_GIT" "$@" || exit $?
    "$REAL_GIT" -C "$2" rev-parse refs/stash > "$WORK/owned"
    printf unrelated > "$2/external"
    "$REAL_GIT" -C "$2" stash push -qu -m external
else
    exec "$REAL_GIT" "$@"
fi
EOF
    chmod +x "$WORK/stub/git"
    run bash -c 'PATH="$1:$PATH" git-worktree-update -C "$2" --json --no-github-account-resolve 2>"$3"' \
        -- "$WORK/stub" "$WORK/repo" "$WORK/errors"
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' <<< "$output")" = StashFailed ]
    [ "$(git -C "$WORK/repo" stash list | wc -l)" -eq 2 ]
    git -C "$WORK/repo" stash list --format=%H | grep -Fx "$(cat "$WORK/owned")"
    [ "$(cat "$WORK/repo/file")" = 'local edit' ]
    [ ! -e "$WORK/repo/external" ]
    grep -q 'ownership changed' "$WORK/errors"
}

@test "stash drop failure is reported and does not claim an entirely successful update" {
    printf 'local edit\n' > "$WORK/repo/file"
    advance_upstream
    mkdir "$WORK/stub"
    cat > "$WORK/stub/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$3" == stash && "$4" == drop ]]; then
    echo 'controlled drop failure' >&2
    exit 42
fi
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/stub/git"
    run bash -c 'PATH="$1:$PATH" git-worktree-update -C "$2" --json --no-github-account-resolve 2>"$3"' \
        -- "$WORK/stub" "$WORK/repo" "$WORK/errors"
    [ "$status" -ne 0 ]
    [ "$(jq -r '.[0].status' <<< "$output")" = StashFailed ]
    [ "$(git -C "$WORK/repo" stash list | wc -l)" -eq 1 ]
    [ "$(cat "$WORK/repo/file")" = 'local edit' ]
    grep -q 'controlled drop failure' "$WORK/errors"
}

@test "sequential dirty worktrees preserve prior shared stashes and previews do not stash" {
    git -C "$WORK/repo" branch --track topic origin/main
    git -C "$WORK/repo" worktree add -q "$WORK/linked" topic
    save_prior_stash
    printf 'main edit\n' > "$WORK/repo/file"
    printf 'linked edit\n' > "$WORK/linked/file"
    advance_upstream
    before="$(git -C "$WORK/repo" rev-parse HEAD)"
    run git-worktree-update -C "$WORK/repo" --dry-run --json
    [ "$status" -eq 0 ]
    [ "$(git -C "$WORK/repo" rev-parse refs/stash)" = "$PRIOR" ]
    [ "$(git -C "$WORK/repo" rev-parse HEAD)" = "$before" ]
    run git-worktree-update -C "$WORK/repo" --json --no-github-account-resolve
    [ "$status" -eq 0 ]
    [ "$(jq '[.[]|select(.status=="Updated" and .stashed)]|length' <<< "$output")" -eq 2 ]
    [ "$(cat "$WORK/repo/file")" = 'main edit' ]
    [ "$(cat "$WORK/linked/file")" = 'linked edit' ]
    [ "$(git -C "$WORK/repo" rev-parse refs/stash)" = "$PRIOR" ]
}

@test "path-addressed operations use the target owner not the caller repository" {
    git clone -q "$WORK/upstream.git" "$WORK/other"
    git -C "$WORK/other" branch topic
    git -C "$WORK/repo" branch topic
    git -C "$WORK/other" worktree add -q "$WORK/linked" topic
    cd "$WORK/repo"
    run git-worktree-switch --path "$WORK/linked"
    [ "$status" -eq 0 ]
    [ "$output" = "$WORK/linked" ]
    run git-worktree-lock --path "$WORK/linked" --reason test
    [ "$status" -eq 0 ]
    run git-worktree-unlock --path "$WORK/linked"
    [ "$status" -eq 0 ]
    run git-worktree-move --path "$WORK/linked" ../moved
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "$WORK/moved" ]
    run git-worktree-remove --path "$WORK/moved" --delete-branch
    [ "$status" -eq 0 ]
    git -C "$WORK/repo" show-ref --verify --quiet refs/heads/topic
    ! git -C "$WORK/other" show-ref --verify --quiet refs/heads/topic
}

@test "path targets work outside repositories but reject child dirs invalid selectors and root moves" {
    git -C "$WORK/repo" worktree add -qb topic "$WORK/linked"
    mkdir "$WORK/linked/child"
    cd "$WORK"
    run git-worktree-switch --path "$WORK/linked"
    [ "$status" -eq 0 ]
    run git-worktree-switch --path "$WORK/linked/child"
    [ "$status" -ne 0 ]
    run git-worktree-switch -C "$WORK/missing" --path "$WORK/linked"
    [ "$status" -ne 0 ]
    run git-worktree-move --path "$WORK/repo" "$WORK/root-moved"
    [ "$status" -ne 0 ]
    [[ "$output" == *'main/root worktree'* ]]
    run git-worktree-remove --path "$WORK/linked" --dry-run
    [ "$status" -eq 0 ]
    [ -d "$WORK/linked" ]
    run git-worktree-switch topic
    [ "$status" -ne 0 ]
}

@test "deleted target paths require the caller or explicit repository" {
    git -C "$WORK/repo" worktree add -qb topic "$WORK/linked"
    rm -rf "$WORK/linked"
    cd "$WORK"
    run git-worktree-remove --path "$WORK/linked" --force
    [ "$status" -ne 0 ]
    run git-worktree-remove -C "$WORK/repo" --path "$WORK/linked" --force
    [ "$status" -eq 0 ]
}

@test "bash completion uses explicit repository and excludes checked-out branches" {
    git -C "$WORK/repo" branch free
    git -C "$WORK/repo" branch busy
    git -C "$WORK/repo" worktree add -q "$WORK/linked" busy
    git -C "$WORK/seed" branch caller-only
    cd "$WORK/seed"
    run bash -c 'source "$1"; COMP_WORDS=(git-worktree-add --path "$2" ""); COMP_CWORD=3; _shm_git_complete; printf "%s\n" "${COMPREPLY[@]}"' \
        -- "$REPO_ROOT/completions/bash/shm-git-completion.bash" "$WORK/repo"
    [ "$status" -eq 0 ]
    [ "$output" = free ]
    run bash -c 'source "$1"; COMP_WORDS=(git-worktree-switch -C "$2" ""); COMP_CWORD=3; _shm_git_complete; printf "%s\n" "${COMPREPLY[@]}"' \
        -- "$REPO_ROOT/completions/bash/shm-git-completion.bash" "$WORK/repo"
    [[ "$output" == *main* && "$output" == *busy* && "$output" != *caller-only* ]]
    for path in "$WORK/missing" '$(touch SHOULD_NOT_EXIST)' ""; do
        run bash -c 'source "$1"; COMP_WORDS=(git-worktree-add -C "$2" ""); COMP_CWORD=3; _shm_git_complete; printf "%s\n" "${COMPREPLY[@]}"' \
            -- "$REPO_ROOT/completions/bash/shm-git-completion.bash" "$path"
        [ "$output" = "" ]
    done
    [ ! -e SHOULD_NOT_EXIST ]
}

@test "zsh completion honors explicit repository without evaluating its path" {
    command -v zsh >/dev/null || skip 'zsh is not installed'
    git -C "$WORK/repo" branch free
    git -C "$WORK/seed" branch caller-only
    cd "$WORK/seed"
    run zsh -f -c 'compdef() { :; }; zstyle() { :; }; source "$1"; words=(git-worktree-add -C "$2" ""); CURRENT=4; _shm_local_branches' \
        -- "$REPO_ROOT/completions/zsh/shm-git-completion.zsh" "$WORK/repo"
    [ "$status" -eq 0 ]
    [ "$output" = free ]
    run zsh -f -c 'compdef() { :; }; zstyle() { :; }; source "$1"; words=(git-worktree-add -C "$2" ""); CURRENT=4; _shm_local_branches' \
        -- "$REPO_ROOT/completions/zsh/shm-git-completion.zsh" '$(touch SHOULD_NOT_EXIST)'
    [ "$output" = "" ]
    [ ! -e SHOULD_NOT_EXIST ]
}

@test "bash completion registers new Git commands and worktree migration flags" {
    run bash -c 'source "$1"; complete -p git-branch-list git-tag-list git-branch-switch git-branch-remove git-stash-save git-stash-restore git-config-set git-restore' \
        -- "$REPO_ROOT/completions/bash/shm-git-completion.bash"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 8 ]
    run bash -c 'source "$1"; COMP_WORDS=(git-worktree-remove --); COMP_CWORD=1; _shm_git_complete; printf "%s\n" "${COMPREPLY[@]}"' \
        -- "$REPO_ROOT/completions/bash/shm-git-completion.bash"
    [[ "$output" == *--keep-branch* && "$output" == *--delete-branch=false* && "$output" == *--confirm* ]]
    run bash -c 'source "$1"; COMP_WORDS=(git-config-set --scope ""); COMP_CWORD=2; _shm_git_complete; printf "%s\n" "${COMPREPLY[@]}"' \
        -- "$REPO_ROOT/completions/bash/shm-git-completion.bash"
    [ "$output" = $'local\nglobal\nsystem' ]
}

@test "zsh completion dispatches new command and migration options" {
    command -v zsh >/dev/null || skip 'zsh is not installed'
    run zsh -f -c 'compdef() { :; }; zstyle() { :; }; _arguments() { printf "%s\n" "$@"; }; source "$1"; words=(git-config-set --); _shm_git_command' \
        -- "$REPO_ROOT/completions/zsh/shm-git-completion.zsh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'local global system'* && "$output" == *--confirm* ]]
    run zsh -f -c 'compdef() { :; }; zstyle() { :; }; _arguments() { printf "%s\n" "$@"; }; source "$1"; words=(git-worktree-remove --); _shm_git_command' \
        -- "$REPO_ROOT/completions/zsh/shm-git-completion.zsh"
    [ "$status" -eq 0 ]
    [[ "$output" == *--keep-branch* && "$output" == *'true false'* && "$output" == *--confirm* ]]
}
