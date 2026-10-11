#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    WORK="$(mktemp -d)"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
    export GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_EMAIL=test@example.com
    git init -q -b main "$WORK/main"
    printf 'initial\n' > "$WORK/main/file"
    git -C "$WORK/main" add file
    git -C "$WORK/main" commit -qm initial
    git -C "$WORK/main" worktree add -qb feature/rebase "$WORK/linked"
    printf 'feature change\n' > "$WORK/linked/file"
    git -C "$WORK/linked" commit -qam feature
    printf 'main change\n' > "$WORK/main/file"
    git -C "$WORK/main" commit -qam main
    git -C "$WORK/main" worktree add -q --detach "$WORK/detached"
}

teardown() { rm -rf -- "$WORK"; }

assert_rebase_identity() {
    run git-status-summary -C "$WORK/linked" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r .branch <<< "$output")" = feature/rebase ]
    [[ "$(jq -r .operation <<< "$output")" == *REBASE* ]]
    [[ "$(jq -r .statusString <<< "$output")" == '[feature/rebase|'* ]]
    run git-worktree-list -C "$WORK/main" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r --arg path "$WORK/linked" '.[]|select(.path==$path)|[.branch,.detached]|@tsv' <<< "$output")" = $'feature/rebase\ttrue' ]
    [ "$(jq -r --arg path "$WORK/main" '.[]|select(.path==$path)|[.branch,.detached]|@tsv' <<< "$output")" = $'main\tfalse' ]
    [ "$(jq -r --arg path "$WORK/detached" '.[]|select(.path==$path)|[.branch,.detached]|@tsv' <<< "$output")" = $'(detached)\ttrue' ]
    run git-status-summary -C "$WORK/detached" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.branch,.operation]|@tsv' <<< "$output")" = $'HEAD\t' ]
    [ "$(git -C "$WORK/linked" rev-parse --abbrev-ref HEAD)" = HEAD ]
}

@test "merge-backend paused rebase retains original linked branch without changing detached state" {
    run git -C "$WORK/linked" rebase --merge main
    [ "$status" -eq 1 ]
    assert_rebase_identity
    run git-status-summary -C "$WORK/linked" --string
    [[ "$output" == '[feature/rebase|REBASE'* ]]
    git -C "$WORK/linked" rebase --abort
    [ "$(git -C "$WORK/linked" rev-parse --abbrev-ref HEAD)" = feature/rebase ]
}

@test "apply-backend paused rebase uses worktree-specific head-name metadata" {
    run git -C "$WORK/linked" rebase --apply main
    [ "$status" -eq 1 ]
    assert_rebase_identity
    git -C "$WORK/linked" rebase --abort
}

@test "conflicted merges retain target branch without pretending HEAD is detached" {
    run git -C "$WORK/linked" merge main
    [ "$status" -eq 1 ]
    run git-status-summary -C "$WORK/linked" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.branch,.operation]|@tsv' <<< "$output")" = $'feature/rebase\tMERGING' ]
    [ "$(jq .conflicts <<< "$output")" -gt 0 ]
    run git-worktree-list -C "$WORK/main" --json
    [ "$(jq -r --arg path "$WORK/linked" '.[]|select(.path==$path)|[.branch,.detached]|@tsv' <<< "$output")" = $'feature/rebase\tfalse' ]
    git -C "$WORK/linked" merge --abort
}

@test "invalid rebase refs do not invent branch names or execute metadata as shell code" {
    git_dir="$(git -C "$WORK/detached" rev-parse --absolute-git-dir)"
    mkdir "$git_dir/rebase-merge"
    for ref in 'detached HEAD' 'refs/remotes/origin/main' 'refs/heads/bad ref' 'refs/heads/$(touch BAD)'; do
        printf '%s\n' "$ref" > "$git_dir/rebase-merge/head-name"
        run git-status-summary -C "$WORK/detached" --json
        [ "$status" -eq 0 ]
        [ "$(jq -r .branch <<< "$output")" = HEAD ]
        run git-worktree-list -C "$WORK/main" --json
        [ "$(jq -r --arg path "$WORK/detached" '.[]|select(.path==$path)|.branch' <<< "$output")" = '(detached)' ]
        [ ! -e BAD ]
    done
}
