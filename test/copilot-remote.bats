#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/bin" "$WORK/repo" "$WORK/plain" "$WORK/home/session-state"
    export COPILOT_HOME="$WORK/home" RECORD="$WORK/record"
    export GIT_CEILING_DIRECTORIES="$WORK"
    export PATH="$WORK/bin:$REPO_ROOT/bin:$PATH"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$RECORD"\n' > "$WORK/bin/copilot"
    chmod +x "$WORK/bin/copilot"
    git -C "$WORK/repo" init -q
    cd "$WORK/repo"
}

teardown() { cd "$REPO_ROOT"; rm -rf -- "$WORK"; }

plan() {
    copilot-launch-plan --no-resume --json "$@" > "$WORK/plan" 2> "$WORK/error"
}

@test "remote accepts supported GitHub origins without implicitly opting in" {
    local url
    for url in https://github.com/owner/repo.git git@github.com:owner/repo ssh://git@github.com/owner/repo.git HTTPS://GITHUB.COM/Owner/Repo; do
        git config remote.origin.url "$url"
        plan --remote
        jq -e '(.args|index("--remote")) != null and (.args|index("--no-remote")) == null' "$WORK/plan"
        [ ! -s "$WORK/error" ]
        plan
        jq -e '(.args|index("--remote")) == null' "$WORK/plan"
    done
}

@test "remote stays local for missing non-GitHub misleading and ambiguous origins" {
    local url
    for url in '' https://example.invalid/owner/repo https://github.com.evil.invalid/owner/repo https://github.com/owner/repo/extra https://github.com/owner/..; do
        git config remote.origin.url "$url"
        plan --remote
        jq -e '(.args|index("--remote")) == null and (.args|index("--no-remote")) != null' "$WORK/plan"
        grep -q 'Continuing locally' "$WORK/error"
    done
    git config remote.origin.url https://github.com/owner/repo
    git config --add remote.origin.url https://github.com/other/repo
    plan --remote
    jq -e '(.args|index("--remote")) == null' "$WORK/plan"
    cd "$WORK/plain"
    plan --remote
    grep -q 'Continuing locally' "$WORK/error"
}

@test "explicit disable wins before and after separator and preserves argument values" {
    git remote add origin https://github.com/owner/repo
    plan --remote -- --no-remote --remote
    jq -e '(.args|index("--remote")) == null and ([.args[]|select(.=="--no-remote")]|length)==1' "$WORK/plan"
    [ ! -s "$WORK/error" ]
    plan --remote -- --no-remote-export
    jq -e '(.args|index("--remote")) == null and (.args|index("--no-remote-export")) != null' "$WORK/plan"
    plan --prompt --remote
    jq -e '.args[(-1)]=="--remote" and (.args|index("--no-remote"))==null' "$WORK/plan"
}

@test "effective directory and resumed launch ignore stale session metadata" {
    git remote add origin https://github.com/owner/repo
    mkdir -p "$COPILOT_HOME/session-state/session"
    printf 'cwd: %s\nrepository: owner/repo\n' "$PWD" > "$COPILOT_HOME/session-state/session/workspace.yaml"
    plan -C "$WORK/plain" --resume-session session --remote
    jq -e '(.args|index("session"))!=null and (.args|index("--no-remote"))!=null' "$WORK/plan"
    cd "$WORK/plain"
    plan -C "$WORK/repo" --resume-session session --remote
    jq -e '(.args|index("--remote"))!=null' "$WORK/plan"
    plan --remote -- -C "$WORK/repo"
    jq -e '(.args|index("--remote"))!=null' "$WORK/plan"
}

@test "actual invocation and previews share gated remote arguments" {
    run start-copilot --no-resume --remote
    [ "$status" -eq 0 ]
    grep -qx -- --no-remote "$RECORD"
    ! grep -qx -- --remote "$RECORD"
    rm "$RECORD"
    run start-copilot --dry-run --remote
    [ "$status" -eq 0 ]
    [[ "$output" == *--no-remote* ]]
    [ ! -e "$RECORD" ]
    run copilot-launch-plan help --remote --json
    [ "$status" -eq 0 ]
    jq -e '.passthrough and (.args|index("--remote"))!=null' <<< "$output"
}
