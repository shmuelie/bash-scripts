#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-scope-$$-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/home/session-state" "$WORK/project" "$WORK/non-git" "$WORK/bin"
    export COPILOT_HOME="$WORK/home" CANDIDATES="$WORK/candidates"
    export GIT_CEILING_DIRECTORIES="$WORK"
    printf '#!/usr/bin/env bash\nexit 99\n' > "$WORK/bin/copilot"
    printf '#!/usr/bin/env bash\ncat > "$CANDIDATES"\njq "{id:.[0].id}" "$CANDIDATES"\n' > "$WORK/bin/selector"
    chmod +x "$WORK/bin/"*
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    cd "$WORK/project"
    git init -q -b main
    git remote add origin https://github.com/Owner/Repo.git
}

teardown() { cd "$REPO_ROOT"; rm -rf -- "$WORK"; }

fixture() {
    local id="$1" repo="$2" branch="$3" cwd="$4" updated="${5-2026-01-01T00:00:00Z}"
    mkdir -p "$COPILOT_HOME/session-state/$id"
    printf 'name: %s\nrepository: %s\nbranch: %s\ncwd: %s\nupdated_at: %s\n' \
        "$id" "$repo" "$branch" "$cwd" "$updated" > "$COPILOT_HOME/session-state/$id/workspace.yaml"
}

ids() { jq -r 'map(.id) | join(",")'; }

@test "moved sessions match single GitHub origin and exact branch newest first" {
    fixture old owner/repo main /old/worktree
    fixture newer OWNER/REPO main /another/move 2026-01-02T00:00:00Z
    fixture wrong-repo someone/repo main "$PWD"
    fixture wrong-case owner/repo Main "$PWD"
    fixture wrong-branch owner/repo other "$PWD"
    local remote
    for remote in https://github.com/Owner/Repo.git git@github.com:Owner/Repo.git \
        ssh://git@github.com/Owner/Repo/; do
        git remote set-url origin "$remote"
        run copilot-session list --json
        [ "$status" -eq 0 ]
        [ "$(printf '%s' "$output" | ids)" = newer,old ]
        run copilot-launch-plan --selector selector --json
        [ "$status" -eq 0 ]
        [ "$(ids < "$CANDIDATES")" = newer,old ]
    done
}

@test "legacy local metadata is eligible but complete identities win automatic resume" {
    fixture full owner/repo main /old/worktree
    fixture legacy '' main "$PWD" 2026-01-03T00:00:00Z
    fixture missing-branch owner/repo '' "$PWD" 2026-01-02T00:00:00Z
    fixture incomplete-conflict someone/repo '' "$PWD"
    fixture branch-conflict '' other "$PWD"
    fixture moved-incomplete '' main /old/worktree
    run copilot-session list --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = legacy,missing-branch,full ]
    run copilot-launch-plan --json
    [ "$status" -eq 0 ]
    [[ "$output" == *full* ]]
    [ ! -e "$CANDIDATES" ]
    rm -rf "$COPILOT_HOME/session-state/full"
    run copilot-launch-plan --selector selector --no-auto-resume --json
    [ "$status" -eq 0 ]
    [ "$(ids < "$CANDIDATES")" = legacy ]
}

@test "unresolved origins fall back only to local paths without known branch conflicts" {
    fixture local owner/repo main "$PWD"
    fixture moved owner/repo main /old/worktree
    fixture wrong-branch owner/repo other "$PWD"
    git remote set-url origin https://example.invalid/owner/repo
    run copilot-session list --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = local ]
    git remote set-url origin https://github.com/owner/repo
    git config --add remote.origin.url git@github.com:owner/repo
    run copilot-session list --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = local ]
    cd "$WORK/non-git"
    fixture outside someone/repo other "$PWD"
    run copilot-session list --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = outside ]
}

@test "explicit global recorded-path and ID filters never inherit implicit identity scope" {
    fixture moved owner/repo main /old/worktree
    fixture conflict other/repo other "$PWD"
    run copilot-session list --all --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = conflict,moved ]
    run copilot-session list --cwd "$PWD" --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = conflict ]
    run copilot-session list --id conflict --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | ids)" = conflict ]
    run copilot-session select --selector selector --stay-in-directory --dry-run --first 1
    [ "$status" -eq 0 ]
    [[ "$output" == *conflict* ]]
}
