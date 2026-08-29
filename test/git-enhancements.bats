#!/usr/bin/env bats
# Functional coverage for Git issues #8, #9, #10, #11, and #13.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    WORK="$REPO_ROOT/.test-work-git-enhancements-${BATS_TEST_NUMBER:-0}-$$-$RANDOM"
    export WORK
    mkdir -p "$WORK"
    export SOURCE_REPOS="$WORK/repos"
    export GITHUB_USER=tester
    REAL_GIT="$(command -v git)"
    export REAL_GIT

    git init -q -b main "$WORK/seed"
    git -C "$WORK/seed" config user.email dev@example.com
    git -C "$WORK/seed" config user.name Dev
    printf 'initial\n' > "$WORK/seed/file.txt"
    git -C "$WORK/seed" add .
    git -C "$WORK/seed" commit -qm initial
    git clone -q --bare "$WORK/seed" "$WORK/upstream.git"
}

teardown() {
    rm -rf "$WORK"
}

clone_layout() {
    local org="${1:-acme}" name="${2:-widget}" path
    path="$SOURCE_REPOS/$org/$name/main"
    mkdir -p "$(dirname "$path")"
    git clone -q "$WORK/upstream.git" "$path"
    git -C "$path" config user.email dev@example.com
    git -C "$path" config user.name Dev
    printf '%s\n' "$path"
}

@test "repository --path targeting works from outside without changing cwd" {
    repo="$(clone_layout)"
    mkdir -p "$repo/sub/dir"
    original="$PWD"

    run git-status-summary --path "$repo/sub" --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .branch)" = main ]
    [ "$PWD" = "$original" ]

    run git-worktree-root --path "$repo/sub"
    [ "$status" -eq 0 ]
    [ "$output" = "$repo" ]
    run git-worktree-current --path "$repo/sub/dir"
    [ "$status" -eq 0 ]
    [ "$output" = "$repo" ]
    run git-worktree-path --path "$repo" feature/target
    [ "$status" -eq 0 ]
    [ "$output" = "$SOURCE_REPOS/acme/widget/feature/target" ]
}

@test "new and add accept custom destinations and surface git errors" {
    repo="$(clone_layout)"
    custom_new="$WORK/custom new"
    run git-worktree-new --path "$repo" --worktree-path "$custom_new" --kind feature custom
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "$custom_new" ]
    [ -f "$custom_new/.git" ]

    git -C "$repo" branch feature/existing
    custom_add="$WORK/custom existing"
    run git-worktree-add --path "$repo" --worktree-path "$custom_add" feature/existing
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "$custom_add" ]

    run git-worktree-add --path "$repo" --worktree-path "$WORK/duplicate" missing-branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid reference"* || "$output" == *"not a valid object"* ]]
}

@test "explicit invalid repository paths fail clearly" {
    run git-worktree-list --path "$WORK/not-a-repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Git repository path not found"* ]]

    run git-sync --path "$WORK/seed/.git/objects"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not a git repository"* ]]
}

@test "worktree list exposes detached locked and prunable state with reasons" {
    repo="$(clone_layout)"
    detached="$WORK/detached"
    locked="$WORK/locked"
    missing="$WORK/missing"
    git -C "$repo" worktree add -q --detach "$detached"
    git -C "$repo" branch feature/locked
    git -C "$repo" worktree add -q "$locked" feature/locked
    git -C "$repo" worktree lock --reason 'long running test' "$locked"
    git -C "$repo" branch feature/missing
    git -C "$repo" worktree add -q "$missing" feature/missing
    rm -rf "$missing"

    run git-worktree-list --path "$repo" --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r --arg p "$detached" '.[]|select(.path==$p)|.detached')" = true ]
    [ "$(printf '%s' "$output" | jq -r --arg p "$locked" '.[]|select(.path==$p)|[.locked,.lockReason]|@tsv')" = $'true\tlong running test' ]
    [ "$(printf '%s' "$output" | jq -r --arg p "$missing" '.[]|select(.path==$p)|.prunable')" = true ]
    [ -n "$(printf '%s' "$output" | jq -r --arg p "$missing" '.[]|select(.path==$p)|.prunableReason')" ]

    run git-worktree-remove -C "$repo" --path "$missing" --force
    [ "$status" -eq 0 ]
    ! git-worktree-list --path "$repo" --json | jq -e --arg p "$missing" '.[]|select(.path==$p)' >/dev/null

    run git-worktree-list --path "$WORK/upstream.git" --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[0].bare')" = true ]
    [ "$(printf '%s' "$output" | jq -r '.[0].lockReason')" = '' ]
}

@test "switch and remove resolve actual custom and detached paths" {
    repo="$(clone_layout)"
    custom="$WORK/nonstandard-location"
    detached="$WORK/detached-location"
    git -C "$repo" branch feature/custom
    git -C "$repo" worktree add -q "$custom" feature/custom
    git -C "$repo" worktree add -q --detach "$detached"

    run git-worktree-switch -C "$repo" feature/custom
    [ "$status" -eq 0 ]
    [ "$output" = "$custom" ]
    run git-worktree-switch -C "$repo" --path "$detached"
    [ "$status" -eq 0 ]
    [ "$output" = "$detached" ]
    run git-worktree-remove -C "$repo" --path "$detached" --force
    [ "$status" -eq 0 ]
    [ ! -e "$detached" ]
    run git-worktree-remove -C "$repo" --delete-branch feature/custom
    [ "$status" -eq 0 ]
    ! git -C "$repo" show-ref --verify --quiet refs/heads/feature/custom
}

@test "stdin worktree removal continues after individual missing branches" {
    repo="$(clone_layout)"
    custom="$WORK/batch-worktree"
    git -C "$repo" branch feature/batch
    git -C "$repo" worktree add -q "$custom" feature/batch

    run bash -c "printf 'missing-one\nfeature/batch\nmissing-two\n' |
        git-worktree-remove -C '$repo' --force"
    [ "$status" -ne 0 ]
    [ ! -e "$custom" ]
    [[ "$output" == *"missing-one"* ]]
    [[ "$output" == *"missing-two"* ]]
}

@test "lock unlock and move operate on resolved worktrees and refuse root" {
    repo="$(clone_layout)"
    old="$WORK/movable"
    moved="$WORK/moved worktree"
    git -C "$repo" branch feature/move
    git -C "$repo" worktree add -q "$old" feature/move

    run git-worktree-lock -C "$repo" --reason maintenance feature/move
    [ "$status" -eq 0 ]
    [ "$(git-worktree-list --path "$repo" --json | jq -r --arg p "$old" '.[]|select(.path==$p)|.lockReason')" = maintenance ]
    run git-worktree-unlock -C "$repo" "$old"
    [ "$status" -eq 0 ]
    run git-worktree-move -C "$repo" feature/move "$moved"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "$moved" ]
    [ -f "$moved/.git" ]

    run git-worktree-move -C "$repo" main "$WORK/nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"main/root worktree"* ]]
}

@test "prune supports dry-run expire and repair honors dry-run" {
    repo="$(clone_layout)"
    stale="$WORK/stale"
    git -C "$repo" branch feature/stale
    git -C "$repo" worktree add -q "$stale" feature/stale
    rm -rf "$stale"

    run git-worktree-prune --path "$repo" --dry-run --expire now
    [ "$status" -eq 0 ]
    [[ "$output" == *"worktrees/stale"* ]]
    git-worktree-list --path "$repo" --json | jq -e --arg p "$stale" '.[]|select(.path==$p)' >/dev/null

    run git-worktree-repair -C "$repo" --dry-run "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"What if:"* ]]
}

@test "worktree update targets another repository and reports paths" {
    repo="$(clone_layout)"
    git -C "$WORK/seed" commit -q --allow-empty -m advance
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main

    run git-worktree-update --path "$repo" --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.branch=="main")|.status')" = Updated ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.branch=="main")|.path')" = "$repo" ]
}

@test "worktree update returns nonzero after reporting a failed merge" {
    repo="$(clone_layout)"
    git -C "$WORK/seed" commit -q --allow-empty -m advance
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    mkdir -p "$WORK/fail-merge"
    cat > "$WORK/fail-merge/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    [[ "$arg" == merge ]] && exit 1
done
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/fail-merge/git"

    run env PATH="$WORK/fail-merge:$PATH" git-worktree-update --path "$repo" --json
    [ "$status" -ne 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.branch=="main")|.status')" = Failed ]
}

@test "update-all filters repositories and returns structured JSON" {
    one="$(clone_layout acme one)"
    clone_layout other two >/dev/null
    clone_layout acme skip-old >/dev/null

    run git-worktree-update-all --path "$SOURCE_REPOS" --organization 'ac*' \
        --name 'o*,skip-*' --exclude '*old' --jobs 2 --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq 'length')" -eq 1 ]
    [ "$(printf '%s' "$output" | jq -r '.[0]|[.organization,.repository,.path,.status]|@tsv')" = $'acme\tone\t'"$one"$'\tCompleted' ]
    [ "$(find "$SOURCE_REPOS" -maxdepth 1 -name '.git-worktree-update-all.*' | wc -l)" -eq 0 ]
}

@test "update-all default human output renders without jq errors" {
    clone_layout acme one >/dev/null
    run git-worktree-update-all --path "$SOURCE_REPOS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"acme/one  [Completed]"* ]]
    [[ "$output" == *"main  Current"* ]]
    [[ "$output" != *"jq: error"* ]]
}

@test "update-all continues after repository failure and changed-only retains context" {
    good="$(clone_layout acme good)"
    bad="$(clone_layout acme bad)"
    git -C "$bad" remote set-url origin "$WORK/missing.git"
    git -C "$WORK/seed" commit -q --allow-empty -m advance
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main

    run bash -c "git-worktree-update-all --path '$SOURCE_REPOS' --jobs 2 --json 2>'$WORK/update-all.err'"
    [ "$status" -ne 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.repository=="bad")|.status')" = Failed ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.repository=="good")|.status')" = Completed ]
    [ "$(git -C "$good" rev-parse HEAD)" = "$(git -C "$WORK/seed" rev-parse HEAD)" ]

    git -C "$WORK/seed" commit -q --allow-empty -m again
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    run bash -c "git-worktree-update-all --path '$SOURCE_REPOS' --changed-only --json 2>'$WORK/update-all-changed.err'"
    [ "$status" -ne 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.repository=="good")|[.organization,.repository,.status]|@tsv')" = $'acme\tgood\tUpdated' ]
    [ "$(printf '%s' "$output" | jq -r '.[]|select(.repository=="bad")|.status')" = Failed ]
}

@test "update-all honors the jobs throttle with isolated worker output" {
    clone_layout acme one >/dev/null
    clone_layout acme two >/dev/null
    clone_layout acme three >/dev/null
    mkdir -p "$WORK/parallel-stub" "$WORK/parallel-state/active"
    cat > "$WORK/parallel-stub/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == fetch ]]; then
        marker="$PARALLEL_STATE/active/$$"
        : > "$marker"
        find "$PARALLEL_STATE/active" -type f | wc -l >> "$PARALLEL_STATE/counts"
        sleep 0.2
        rm -f "$marker"
        exit 0
    fi
done
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/parallel-stub/git"
    export PARALLEL_STATE="$WORK/parallel-state"

    run env PATH="$WORK/parallel-stub:$PATH" git-worktree-update-all \
        --path "$SOURCE_REPOS" --jobs 2 --no-github-account-resolve --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq 'length')" -eq 3 ]
    awk '$1 >= 2 { found=1 } END { exit !found }' "$PARALLEL_STATE/counts"
    ! find "$SOURCE_REPOS" -maxdepth 1 -name '.git-worktree-update-all.*' | grep -q .
}

make_auth_stubs() {
    mkdir -p "$WORK/stub"
    cat > "$WORK/stub/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "auth status" ]]; then
    cat <<'STATUS'
github.com
  ✓ Logged in to github.com account bad-user (keyring)
  - Active account: true
  ✓ Logged in to github.com account good-user (keyring)
  - Active account: false
STATUS
elif [[ "$1 $2" == "auth token" ]]; then
    [[ "${FAIL_TOKENS:-0}" == 1 ]] && exit 1
    account=''
    while [[ $# -gt 0 ]]; do
        [[ "$1" == --user ]] && { account="$2"; break; }
        shift
    done
    printf 'token-%s\n' "$account"
else
    exit 1
fi
EOF
    cat > "$WORK/stub/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == fetch ]]; then
        printf '%s\n' "${GH_TOKEN:-plain}" >> "$AUTH_LOG"
        if [[ "${GH_TOKEN:-}" == token-bad-user ]]; then
            echo 'remote: Repository not found' >&2
            exit 128
        fi
        echo '   abc1234..def5678  main       -> origin/main' >&2
        exit 0
    fi
done
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/stub/gh" "$WORK/stub/git"
}

@test "account-aware fetch retries accounts, caches the winner, and keeps tokens child-only" {
    repo="$(clone_layout)"
    git -C "$repo" remote set-url origin git@github.com:acme/widget.git
    git -C "$repo" remote add mirror https://github.com/acme/widget.git
    make_auth_stubs
    export AUTH_LOG="$WORK/auth.log"
    unset GH_TOKEN GH_HOST

    run env PATH="$WORK/stub:$PATH" git-sync --path "$repo" --json
    [ "$status" -eq 0 ]
    [ "$(cat "$AUTH_LOG")" = $'token-bad-user\ntoken-good-user\ntoken-good-user' ]
    [ -z "${GH_TOKEN:-}" ]
    [ "$(printf '%s' "$output" | jq -r '.[0].action')" = Updated ]
    [[ "$output" != *token-good-user* ]]
}

@test "explicit account mapping and opt-out control fetch credentials" {
    repo="$(clone_layout)"
    git -C "$repo" remote set-url origin https://github.com/acme/widget.git
    make_auth_stubs
    export AUTH_LOG="$WORK/auth.log"

    run env PATH="$WORK/stub:$PATH" git-sync --path "$repo" \
        --github-account github.com/acme=good-user --json
    [ "$status" -eq 0 ]
    [ "$(cat "$AUTH_LOG")" = token-good-user ]

    : > "$AUTH_LOG"
    run env PATH="$WORK/stub:$PATH" git-sync --path "$repo" \
        --no-github-account-resolve --json
    [ "$status" -eq 0 ]
    [ "$(cat "$AUTH_LOG")" = plain ]

    : > "$AUTH_LOG"
    run env PATH="$WORK/stub:$PATH" FAIL_TOKENS=1 git-sync --path "$repo" \
        --github-account github.com/acme=good-user --json
    [ "$status" -eq 0 ]
    [ "$(cat "$AUTH_LOG")" = plain ]

    : > "$AUTH_LOG"
    run env PATH="$WORK/stub:$PATH" git-worktree-update --path "$repo" \
        --github-account github.com/acme=good-user --json
    [ "$status" -eq 0 ]
    [ "$(cat "$AUTH_LOG")" = token-good-user ]

    run git-sync --path "$repo" --github-account 'github.com/acme=bad user'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid GitHub"* ]]
}

@test "remote URL parser supports HTTPS SSH and SCP forms" {
    run bash -c "source '$REPO_ROOT/lib/common.sh'; source '$REPO_ROOT/lib/git/git-common.sh'; { git_github_remote_info 'https://github.com/acme/widget.git'; git_github_remote_info 'ssh://git@ghe.example.com/acme/widget.git'; git_github_remote_info 'git@github.com:acme/widget.git'; } | tr '\037' '/'"
    [ "$status" -eq 0 ]
    [ "$output" = $'github.com/acme\nghe.example.com/acme\ngithub.com/acme' ]
}

@test "completion files include new commands and account options" {
    run grep -E 'git-worktree-(prune|repair|lock|unlock|move|update-all)' "$REPO_ROOT/completions/bash/shm-git-completion.bash"
    [ "$status" -eq 0 ]
    run grep -F -- '--github-account' "$REPO_ROOT/completions/zsh/shm-git-completion.zsh"
    [ "$status" -eq 0 ]
    run grep -F 'git-status-segment' "$REPO_ROOT/completions/bash/shm-git-completion.bash"
    [ "$status" -eq 0 ]
    run grep -F "zstyle ':completion:*:*:git-worktree-*:*'" "$REPO_ROOT/completions/zsh/shm-git-completion.zsh"
    [ "$status" -eq 0 ]
}
