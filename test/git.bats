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

@test "git-worktree-update fast-forwards a behind worktree" {
    clone_repo
    git -C "$WORK/seed" commit -q --allow-empty -m more
    git -C "$WORK/seed" push -q "$WORK/upstream.git" main
    run bash -c 'git-worktree-update --json | jq -r ".[] | select(.branch==\"main\") | .status"'
    [ "$status" -eq 0 ]
    [ "$output" = "Updated" ]
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

@test "git-repo-repair moves a repo-level clone into a branch subdir" {
    mkdir -p "$SOURCE_REPOS/badorg"
    git clone -q "$WORK/seed" "$SOURCE_REPOS/badorg/badrepo"
    run bash -c "cd /tmp && git-repo-repair --root '$SOURCE_REPOS' --org badorg --json | jq -r '.[0].status'"
    [ "$status" -eq 0 ]
    [ "$output" = "Converted" ]
    [ -d "$SOURCE_REPOS/badorg/badrepo/main/.git" ]
}
