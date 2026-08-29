#!/usr/bin/env bats
# git.bats — functional tests for the git-* commands.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"

    WORK="$(mktemp -d)"
    export WORK
    export SOURCE_REPOS="$WORK/repos"
    export GITHUB_USER=tester

    git config --global init.defaultBranch main >/dev/null 2>&1 || true

    # Seed an upstream repo with one commit on main.
    git init -q -b main "$WORK/seed"
    git -C "$WORK/seed" config user.email dev@example.com
    git -C "$WORK/seed" config user.name Dev
    echo hi > "$WORK/seed/a.txt"
    git -C "$WORK/seed" add .
    git -C "$WORK/seed" commit -qm init
    git clone -q --bare "$WORK/seed" "$WORK/upstream.git"
}

teardown() {
    rm -rf "$WORK"
}

# Clone through git-repo-new and cd into the result.
clone_repo() {
    local tp
    tp="$(git-repo-new "file://$WORK/upstream.git" --org myorg --name myrepo)"
    cd "$tp"
    git config user.email dev@example.com
    git config user.name Dev
}

@test "git-repo-new uses <root>/<org>/<repo>/<branch> layout" {
    run git-repo-new "file://$WORK/upstream.git" --org acme --name widget
    [ "$status" -eq 0 ]
    [ -d "$SOURCE_REPOS/acme/widget/main/.git" ]
    [ "${lines[-1]}" = "$SOURCE_REPOS/acme/widget/main" ]
}

@test "git-repo-new parses GitHub HTTPS URL for org and name" {
    run git-repo-new --dry-run https://github.com/dotnet/runtime --root /tmp/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/x/dotnet/runtime/"* ]]
}

@test "git-repo-new parses Azure DevOps URL for org and name" {
    run git-repo-new --dry-run "https://dev.azure.com/contoso/Platform/_git/runtime" --branch release/v2 --root /tmp/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp/x/contoso/runtime/release/v2"* ]]
}

@test "git-repo-new fails when org cannot be parsed" {
    run git-repo-new --root /tmp/x "file:///some/path.git"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unable to parse"* ]]
}

@test "git-repo-new fails without a root" {
    unset SOURCE_REPOS
    run git-repo-new https://github.com/a/b
    [ "$status" -ne 0 ]
    [[ "$output" == *"No repository root"* ]]
}

@test "git-status-summary reports clean tracking branch" {
    clone_repo
    run git-status-summary --string
    [ "$status" -eq 0 ]
    [ "$output" = "[main ≡]" ]
}

@test "git-status-summary --json reports branch and no changes" {
    clone_repo
    run bash -c 'git-status-summary --json | jq -r ".branch, .hasChanges"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "main" ]
    [ "${lines[1]}" = "false" ]
}

@test "git-status-summary reflects working-tree changes" {
    clone_repo
    echo more >> a.txt
    echo new > b.txt
    run git-status-summary --string
    [[ "$output" == *"~1"* ]]   # modified working file
    [[ "$output" == *"?"* ]]    # untracked present
}

@test "git-status-summary on non-repo reports isGitRepo false" {
    run bash -c "cd '$WORK' && git-status-summary --json | jq -r .isGitRepo"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "git-status-summary reports an unborn branch name" {
    git init -q -b topic "$WORK/empty"
    run bash -c "cd '$WORK/empty' && git-status-summary --json | jq -r '.branch, .statusString'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "topic" ]
    [ "${lines[1]}" = "[topic]" ]
}

@test "git-status-summary reports an unborn cloned branch with upstream" {
    git init -q --bare --initial-branch=main "$WORK/empty.git"
    git clone -q "$WORK/empty.git" "$WORK/empty-clone"
    run bash -c "cd '$WORK/empty-clone' && git-status-summary --json | jq -r '.branch, .upstream'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "main" ]
    [ "${lines[1]}" = "origin/main" ]
}

@test "worktree lifecycle: new, list, switch, remove" {
    clone_repo
    np="$(git-worktree-new feature-x --kind feature)"
    [ -d "$np/.git" ] || [ -f "$np/.git" ]

    run bash -c 'git-worktree-list --json | jq -r ".[].branch"'
    [[ "$output" == *"feature/feature-x"* ]]

    run git-worktree-switch feature/feature-x
    [ "$status" -eq 0 ]
    [ "$output" = "$np" ]

    run git-worktree-remove --delete-branch --force feature/feature-x
    [ "$status" -eq 0 ]
    run bash -c 'git-worktree-list | grep -c feature/feature-x || true'
    [ "$output" = "0" ]
}

@test "git-worktree-new user kind uses GITHUB_USER segment" {
    clone_repo
    run git-worktree-path "user/tester/my-work"
    [ "$status" -eq 0 ]
    expected="$output"
    np="$(git-worktree-new my-work)"   # default kind is user
    [ "$np" = "$expected" ]
    [[ "$np" == *"/user/tester/my-work" ]]
}

@test "git-worktree-new --dry-run creates nothing" {
    clone_repo
    run git-worktree-new --dry-run feature-y --kind feature
    [ "$status" -eq 0 ]
    [[ "$output" == *"What if:"* ]]
    run bash -c 'git-worktree-list | grep -c feature-y || true'
    [ "$output" = "0" ]
}

@test "git-worktree-path computes sibling path from root branch" {
    clone_repo
    run git-worktree-path "feature/z"
    [ "$status" -eq 0 ]
    [ "$output" = "$SOURCE_REPOS/myorg/myrepo/feature/z" ]
}

@test "git-sync reports an updated ref after upstream advances" {
    clone_repo
    # Advance upstream main.
    git -C "$WORK/seed" commit -q --allow-empty -m more
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    run bash -c 'git-sync --json | jq -r ".[] | .action"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated"* ]]
}

@test "git-sync forces a stable C locale for parsed fetch output" {
    mkdir -p "$WORK/stub"
    cat > "$WORK/stub/git" <<'EOF'
#!/usr/bin/env bash
printf '%s/%s\n' "${LC_ALL:-}" "${LANG:-}" > "$LOCALE_LOG"
printf '   abc1234..def5678  main       -> origin/main\n' >&2
EOF
    chmod +x "$WORK/stub/git"
    export LOCALE_LOG="$WORK/locale.log"

    run env PATH="$WORK/stub:$PATH" LANG=fr_FR.UTF-8 LC_ALL= bash -c 'git-sync --json | jq -r ".[0].action"'
    [ "$status" -eq 0 ]
    [ "$output" = "Updated" ]
    [ "$(cat "$LOCALE_LOG")" = "C/C" ]
}

@test "git-worktree-update fast-forwards a behind worktree" {
    clone_repo
    git -C "$WORK/seed" commit -q --allow-empty -m more
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    run bash -c 'git-worktree-update --json | jq -r ".[] | select(.branch==\"main\") | .status"'
    [ "$status" -eq 0 ]
    [ "$output" = "Updated" ]
}

@test "git-worktree-update skips a behind worktree during a merge" {
    clone_repo
    git -C "$WORK/seed" commit -q --allow-empty -m more
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    touch "$(git rev-parse --git-dir)/MERGE_HEAD"

    run bash -c 'git-worktree-update --json | jq -r ".[] | select(.branch==\"main\") | [.status,.operation] | @tsv"'
    [ "$status" -eq 0 ]
    [ "$output" = $'InProgress\tMERGING' ]
}

@test "git-worktree-update reports interactive rebase progress" {
    clone_repo
    git -C "$WORK/seed" commit -q --allow-empty -m more
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    git_dir="$(git rev-parse --git-dir)"
    mkdir -p "$git_dir/rebase-merge"
    printf '1\n' > "$git_dir/rebase-merge/msgnum"
    printf '3\n' > "$git_dir/rebase-merge/end"
    : > "$git_dir/rebase-merge/interactive"

    run bash -c 'git-worktree-update --json | jq -r ".[] | select(.branch==\"main\") | [.status,.operation] | @tsv"'
    [ "$status" -eq 0 ]
    [ "$output" = $'InProgress\tREBASE-i 1/3' ]
}

@test "git-worktree-update reports a missing behind worktree" {
    clone_repo
    missing="$SOURCE_REPOS/myorg/myrepo/missing"
    git worktree add -q -b missing "$missing" origin/main
    git -C "$WORK/seed" commit -q --allow-empty -m more
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    rm -rf "$missing"

    run bash -c 'git-worktree-update --json | jq -r ".[] | select(.branch==\"missing\") | .status"'
    [ "$status" -eq 0 ]
    [ "$output" = "Missing" ]
}

@test "git-worktree-update leaves NoUpstream unchanged when ls-remote fails" {
    clone_repo
    git-worktree-new local-only --kind feature >/dev/null
    real_git="$(command -v git)"
    mkdir -p "$WORK/stub"
    cat > "$WORK/stub/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ls-remote --heads origin"* ]]; then
    echo "remote unavailable" >&2
    exit 128
fi
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/stub/git"
    export REAL_GIT="$real_git"

    run bash -c "PATH='$WORK/stub:$PATH' git-worktree-update --check-remote --json 2>'$WORK/warn' | jq -r '.[] | select(.branch==\"feature/local-only\") | .status'"
    [ "$status" -eq 0 ]
    [ "$output" = "NoUpstream" ]
    grep -q "Skipping remote branch check" "$WORK/warn"
}

@test "git-stale-branch finds a branch whose remote was deleted" {
    clone_repo
    git checkout -q -b user/tester/temp
    git push -q -u origin user/tester/temp
    git checkout -q main
    git push -q origin --delete user/tester/temp
    git-sync >/dev/null 2>&1
    # Use --all so the result is independent of the email-derived user filter.
    run git-stale-branch --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"user/tester/temp"* ]]
}

@test "git-stale-branch user filter derives the user from git user.email" {
    clone_repo
    git config user.email tester@example.com
    git checkout -q -b user/tester/gone
    git push -q -u origin user/tester/gone
    git checkout -q main
    git push -q origin --delete user/tester/gone
    git-sync >/dev/null 2>&1
    run git-stale-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"user/tester/gone"* ]]
}

@test "git-stale-branch excludes never-pushed branches by default" {
    clone_repo
    git checkout -q -b user/tester/local-only

    run git-stale-branch --all
    [ "$status" -eq 0 ]
    [[ "$output" != *"user/tester/local-only"* ]]

    run git-stale-branch --all --include-never-pushed
    [ "$status" -eq 0 ]
    [[ "$output" == *"user/tester/local-only"* ]]
}

@test "git-stale-branch errors outside a repository" {
    run bash -c "cd '$WORK' && git-stale-branch --all"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not a git repository"* ]]
}

@test "git-stale-branch does not classify branches when ls-remote fails" {
    clone_repo
    git checkout -q -b user/tester/local-only
    git remote set-url origin "$WORK/missing-remote.git"

    run git-stale-branch --all --include-never-pushed
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to list remote branches"* ]]
    [[ "$output" != *$'\nuser/tester/local-only'* ]]
}

@test "git-repo-repair moves a repo-level clone into a branch subdir" {
    mkdir -p "$SOURCE_REPOS/badorg"
    git clone -q "$WORK/seed" "$SOURCE_REPOS/badorg/badrepo"
    run bash -c "cd /tmp && git-repo-repair --root '$SOURCE_REPOS' --org badorg --json | jq -r '.[0].status'"
    [ "$status" -eq 0 ]
    [ "$output" = "Converted" ]
    [ -d "$SOURCE_REPOS/badorg/badrepo/main/.git" ]
    [ "$(find "$SOURCE_REPOS/badorg" -maxdepth 1 -name '.*.__layout_tmp.*' | wc -l)" -eq 0 ]
}

@test "pick_one select fallback reads the choice from a terminal input" {
    printf '2\n' > "$WORK/choice"
    run bash -c "
        source '$REPO_ROOT/lib/common.sh'
        have_cmd() { return 1; }
        SHM_TTY_PATH='$WORK/choice'
        printf 'alpha\nbeta\ngamma\n' | pick_one Pick
    "
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == *"beta" ]]
}

@test "pick_one reports a clear error without a controlling terminal" {
    command -v setsid >/dev/null || skip "setsid is required"
    run setsid bash -c "
        source '$REPO_ROOT/lib/common.sh'
        have_cmd() { return 1; }
        printf 'alpha\nbeta\n' | pick_one Pick
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot open a terminal for interactive selection."* ]]
}
