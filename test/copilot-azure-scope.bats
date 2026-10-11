#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$REPO_ROOT/.test-azure-$$-$BATS_TEST_NUMBER"
    mkdir -p "$WORK/home/session-state" "$WORK/project" "$WORK/bin"
    export COPILOT_HOME="$WORK/home" CANDIDATES="$WORK/candidates"
    export GIT_CEILING_DIRECTORIES="$WORK"
    printf '#!/usr/bin/env bash\nexit 99\n' > "$WORK/bin/copilot"
    printf '#!/usr/bin/env bash\ncat > "$CANDIDATES"\njq "{id:.[0].id}" "$CANDIDATES"\n' > "$WORK/bin/selector"
    chmod +x "$WORK/bin/"*
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    cd "$WORK/project"
    git init -q -b feature/topic
    git remote add origin https://dev.azure.com/acme/Project/_git/Repo
}

teardown() { cd "$REPO_ROOT"; rm -rf -- "$WORK"; }

fixture() {
    local id="$1" repo="$2" branch="$3" cwd="$4"
    mkdir -p "$COPILOT_HOME/session-state/$id"
    printf 'name: %s\nrepository: %s\nbranch: %s\ncwd: %s\nupdated_at: 2026-01-01T00:00:00Z\n' \
        "$id" "$repo" "$branch" "$cwd" > "$COPILOT_HOME/session-state/$id/workspace.yaml"
}

@test "Azure HTTPS SSH and legacy origins normalize encoded names and optional suffixes" {
    fixture moved 'ACME/Project Name/Repo Name' feature/topic /old/tree
    fixture second 'acme/Project Name/Repo Name' feature/topic /older/tree
    fixture conflict 'other/Project Name/Repo Name' feature/topic "$PWD"
    fixture branch-case 'acme/Project Name/Repo Name' Feature/topic "$PWD"
    local remote
    for remote in \
        https://dev.azure.com/acme/Project%20Name/_git/Repo%20Name \
        https://dev.azure.com/acme/Project%20Name/_git/Repo%20Name.git/ \
        https://dev.azure.com/acme/DefaultCollection/Project%20Name/_git/Repo%20Name \
        https://acme.visualstudio.com/Project%20Name/_git/Repo%20Name.git \
        https://acme.visualstudio.com/DefaultCollection/Project%20Name/_git/Repo%20Name \
        git@ssh.dev.azure.com:v3/acme/Project%20Name/Repo%20Name \
        ssh://git@ssh.dev.azure.com/v3/acme/Project%20Name/Repo%20Name.git; do
        git remote set-url origin "$remote"
        run copilot-session list --json
        [ "$status" -eq 0 ]
        [ "$(printf '%s' "$output" | jq -r 'map(.id)|join(",")')" = moved,second ]
        run copilot-launch-plan --selector selector --json
        [ "$status" -eq 0 ]
        [ "$(jq -r 'map(.id)|join(",")' "$CANDIDATES")" = moved,second ]
    done
}

@test "malformed Azure origins fail closed and never admit moved candidates" {
    fixture moved acme/Project/Repo feature/topic /old/tree
    fixture local acme/Project/Repo feature/topic "$PWD"
    local remote
    for remote in \
        https://dev.azure.com/acme/Project/_git/Repo/extra \
        https://dev.azure.com/acme/Project/_git/Repo?query \
        https://dev.azure.com/acme/Project/_git/Repo#fragment \
        https://dev.azure.com/acme/Project/_git/Repo% \
        https://dev.azure.com/acme/Project/_git/Repo%2fother \
        https://dev.azure.com/acme/Project/_git/Repo%5cother \
        https://dev.azure.com/acme/Project/_git/Repo%3fquery \
        https://dev.azure.com/acme/Project/_git/Repo%23fragment \
        https://dev.azure.com/acme/Project/_git/%00Repo \
        https://dev.azure.com/acme/Project/_git/Repo%0a \
        https://dev.azure.com/acme/Project/_git/Repo%E2%80%8B \
        https://dev.azure.com/acme/Project/_git/Repo%E2%80%A8 \
        https://dev.azure.com/acme/Project/_git/Repo%FF \
        https://dev.azure.com/acme/Project/_git/%20Repo \
        https://dev.azure.com/acme/Project/_git/Repo%20 \
        https://dev.azure.com/acme/Project/_git/.git \
        https://dev.azure.com/acme/Project/_git/%2e%2e.git \
        https://dev.azure.com/acme/%2e/_git/Repo \
        https://dev.azure.com/-acme/Project/_git/Repo \
        https://user@dev.azure.com/acme/Project/_git/Repo \
        http://dev.azure.com/acme/Project/_git/Repo \
        ssh://git@ssh.dev.azure.com:22/v3/acme/Project/Repo \
        git@ssh.dev.azure.com:v3/acme/DefaultCollection/Project/Repo \
        git@acme.visualstudio.com:v3/acme/Project/Repo \
        'https://dev.azure.com/acme/Project Name/_git/Repo'; do
        git remote set-url origin "$remote"
        run copilot-session list --json
        [ "$status" -eq 0 ]
        [ "$(printf '%s' "$output" | jq -r 'map(.id)|join(",")')" = local ]
        run copilot-launch-plan --json
        [ "$status" -eq 0 ]
        [[ "$output" != *moved* ]]
    done
}

@test "multiple Azure origin entries never establish repository scope even when identical" {
    fixture moved acme/Project/Repo feature/topic /old
    git config --add remote.origin.url https://dev.azure.com/acme/Project/_git/Repo
    run copilot-session list --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
}

@test "encoded Unicode names normalize without treating plus as a space" {
    fixture moved 'acme/Prójèct+Name/Répo 名' feature/topic /old
    git remote set-url origin 'https://dev.azure.com/acme/Pr%C3%B3j%C3%A8ct+Name/_git/R%C3%A9po%20%E5%90%8D.GIT'
    run copilot-session list --json
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[0].id')" = moved ]
}
