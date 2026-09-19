#!/usr/bin/env bats
# Isolated regression coverage for Git ports #32-40, #51 and #53.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$REPO_ROOT/bin:$PATH"
    REAL_GIT="$(command -v git)"
    export REAL_GIT
    WORK="$(mktemp -d)"
    export WORK
    export HOME="$WORK/home" GIT_CONFIG_GLOBAL="$WORK/global" GIT_CONFIG_SYSTEM="$WORK/system"
    export GIT_AUTHOR_NAME=Tester GIT_COMMITTER_NAME=Tester
    export GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_EMAIL=tester@example.com
    export GIT_AUTHOR_DATE='2024-01-01T12:00:00+00:00' GIT_COMMITTER_DATE='2024-01-01T12:00:00+00:00'
    mkdir -p "$HOME"
    repo="$WORK/repository with spaces"
    git init -q -b main "$repo"
    printf 'initial\n' > "$repo/file"
    printf 'ignored\n' > "$repo/.gitignore"
    git -C "$repo" add .
    git -C "$repo" commit -qm "Initial 'quoted' subject!"
}

teardown() {
    rm -rf -- "$WORK"
}

json_is() {
    printf '%s' "$output" | jq -e "$1" >/dev/null
}

make_remote() {
    git clone -q --bare "$repo" "$WORK/remote.git"
    git -C "$repo" remote add origin "$WORK/remote.git"
    git -C "$repo" fetch -q origin
    git -C "$repo" branch -q --set-upstream-to=origin/main main
    git -C "$repo" remote set-head origin main
}

@test "branch discovery exposes full refs, tracking, symbolic HEAD and repository context" {
    make_remote
    git -C "$repo" branch same-commit
    mkdir -p "$repo/subdir"
    run git-branch-list -C "$repo/subdir" --json
    [ "$status" -eq 0 ]
    json_is 'length == 4'
    json_is '[.[]|select(.current)|.branch] == ["main"]'
    json_is '.[]|select(.branch=="main")|.refName=="refs/heads/main" and .upstream=="refs/remotes/origin/main" and .aheadBy==0 and .behindBy==0 and (.upstreamGone|not)'
    json_is '.[]|select(.branch=="origin/HEAD")|.symbolicTarget=="refs/remotes/origin/main" and .isRemote'
    json_is '.[]|select(.branch=="same-commit")|.upstream==null and .aheadBy==null and .behindBy==null'
    [ "$(jq -r '.[0].subject' <<< "$output")" = "Initial 'quoted' subject!" ]
    [ "$(jq -r '.[0].repositoryPath' <<< "$output")" = "$repo/subdir" ]
    run git-branch-list -C "$repo" --local --json
    [ "$status" -eq 0 ]
    json_is 'length==2 and all(.[]; .isRemote|not)'
    run git-branch-list -C "$repo" --remote --json
    json_is 'length==2 and all(.[]; .isRemote)'
    run git-branch-list -C "$repo" --local --remote --json
    json_is 'length==4'
}

@test "branch discovery handles diverged and gone upstreams without fetching" {
    make_remote
    printf 'local\n' > "$repo/local"
    git -C "$repo" add local
    git -C "$repo" commit -qm local
    remote_commit="$(printf 'remote\n' | git -C "$repo" commit-tree 'HEAD~1^{tree}' -p HEAD~1)"
    git -C "$repo" update-ref refs/remotes/origin/main "$remote_commit"
    run git-branch-list -C "$repo" --local --json
    [ "$status" -eq 0 ]
    json_is '.[0].aheadBy==1 and .[0].behindBy==1'
    git -C "$repo" update-ref -d refs/remotes/origin/main
    run git-branch-list -C "$repo" --local --json
    [ "$status" -eq 0 ]
    json_is '.[0].upstreamGone and .[0].aheadBy==null and .[0].behindBy==null'
}

@test "discovery supports unborn, detached, bare and nonrepository failures" {
    git init -q -b newborn "$WORK/empty"
    run git-branch-list -C "$WORK/empty" --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
    run git-tag-list -C "$repo" --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
    git -C "$repo" checkout -q --detach
    run git-branch-list -C "$repo" --json
    [ "$status" -eq 0 ]
    json_is 'all(.[]; .current|not)'
    make_remote
    run git-branch-list -C "$WORK/remote.git" --json
    [ "$status" -eq 0 ]
    json_is '.[0].branch=="main"'
    run git-branch-list -C "$WORK" --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not a git repository"* ]]
}

@test "tag discovery preserves annotations and fully peels noncommit and nested targets" {
    annotation=$'Subject with \'quotes\'! and separators \x1f\n\nBody line\nRecovery instructions.\n'
    printf '%s' "$annotation" > "$WORK/annotation"
    git -C "$repo" tag -a --cleanup=verbatim -F "$WORK/annotation" v1.0
    git -C "$repo" tag v1-light
    git -C "$repo" tag -a -m outer nested v1.0
    blob="$(printf 'blob contents' | git -C "$repo" hash-object -w --stdin)"
    git -C "$repo" tag blob "$blob"
    git -C "$repo" tag tree 'HEAD^{tree}'
    git -C "$repo" tag -a -m 'blob annotation' annotated-blob "$blob"
    run git-tag-list -C "$repo" --json
    [ "$status" -eq 0 ]
    json_is 'length==6'
    json_is '.[]|select(.name=="v1.0")|.isAnnotated and .objectType=="tag" and .targetObjectType=="commit" and .taggerDate=="2024-01-01T12:00:00+00:00"'
    [ "$(jq -r '.[]|select(.name=="v1.0")|.annotation' <<< "$output")" = "$(cat "$WORK/annotation")" ]
    printf '%s' "$output" | jq -e --rawfile annotation "$WORK/annotation" \
        '.[]|select(.name=="v1.0")|.annotation==$annotation' >/dev/null
    json_is '.[]|select(.name=="v1-light")|(.isAnnotated|not) and .annotation==null and .taggerDate==null and .creatorDate!=null'
    json_is '.[]|select(.name=="blob" or .name=="tree" or .name=="annotated-blob")|.targetCommit==null'
    [ "$(jq -r '.[]|select(.name=="nested")|.targetCommit' <<< "$output")" = "$(git -C "$repo" rev-parse HEAD)" ]
    run git-tag-list -C "$repo" --name 'v1*' --name v1.0 --json
    [ "$status" -eq 0 ]
    json_is 'length==2'
    run git-tag-list -C "$repo" --name 'V1*' --json
    [ "$output" = '[]' ]
}

@test "machine ref decoder treats embedded delimiters as data, not record boundaries" {
    mkdir "$WORK/stubs"
    cat > "$WORK/stubs/git" <<'EOF'
#!/usr/bin/env bash
printf "'first'\\000'body\\000contains\\nrecord delimiters'\\n"
EOF
    chmod +x "$WORK/stubs/git"
    run env PATH="$WORK/stubs:$PATH" bash -c \
        'set -o pipefail; source "$1/lib/git/git-ref-info.sh"; git_ref_records . unused 2 refs/tags/' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    json_is '.==[["first","body\u0000contains\nrecord delimiters"]]'
}

@test "discovery propagates native ref failures instead of empty success" {
    mkdir "$WORK/stubs"
    cat > "$WORK/stubs/git" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" for-each-ref "*) echo 'reference inspection failed' >&2; exit 41 ;;
esac
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/stubs/git"
    for command in git-branch-list git-tag-list; do
        run env PATH="$WORK/stubs:$PATH" "$command" -C "$repo" --json
        [ "$status" -eq 41 ]
        [[ "$output" == *"reference inspection failed"* ]]
        [[ "$output" != *'[]'* ]]
    done
}

@test "branch switch preserves changes, creates explicitly and does not guess remotes" {
    make_remote
    git -C "$repo" branch existing
    printf 'dirty\n' >> "$repo/file"
    run git-branch-switch -C "$repo" existing
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" branch --show-current)" = existing ]
    grep -q dirty "$repo/file"
    run git-branch-switch -C "$repo" --create new
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" branch --show-current)" = new ]
    run git-branch-switch -C "$repo" --create --force existing
    [ "$status" -ne 0 ]
    grep -q dirty "$repo/file"
    git -C "$repo" update-ref refs/remotes/origin/remote-only HEAD
    run git-branch-switch -C "$repo" remote-only
    [ "$status" -ne 0 ]
    run git-branch-switch -C "$repo" --track origin/remote-only
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" rev-parse --symbolic-full-name '@{upstream}')" = refs/remotes/origin/remote-only ]
}

@test "branch switch validates operands and preserves worktree protection even with force" {
    git -C "$repo" worktree add -qb occupied "$WORK/occupied"
    for branch in occupied 'HEAD~1' '@{-1}' '--detach' refs/heads/main; do
        run git-branch-switch -C "$repo" --force -- "$branch"
        [ "$status" -ne 0 ]
        [ "$(git -C "$repo" branch --show-current)" = main ]
    done
    run git-branch-switch -C "$repo" --create --track origin/x
    [ "$status" -ne 0 ]
}

@test "branch switching discards changes only when requested and honors preview and refusal" {
    git -C "$repo" branch target
    printf 'dirty\n' >> "$repo/file"
    run git-branch-switch -C "$repo" --force --dry-run target
    [ "$status" -eq 0 ]
    grep -q dirty "$repo/file"
    run bash -c 'printf "n\n" | git-branch-switch -C "$1" --force --confirm target' _ "$repo"
    [ "$status" -eq 0 ]
    grep -q dirty "$repo/file"
    [ "$(git -C "$repo" branch --show-current)" = main ]
    run git-branch-switch -C "$repo" --discard-changes target
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = initial ]
}

@test "local branch deletion is merged-only unless force and refuses checked-out branches" {
    git -C "$repo" branch merged
    run git-branch-remove -C "$repo" refs/heads/merged
    [ "$status" -eq 0 ]
    ! git -C "$repo" show-ref --verify --quiet refs/heads/merged
    extra="$(printf 'unmerged\n' | git -C "$repo" commit-tree 'HEAD^{tree}' -p HEAD)"
    git -C "$repo" branch unmerged "$extra"
    run git-branch-remove -C "$repo" unmerged
    [ "$status" -ne 0 ]
    git -C "$repo" show-ref --verify --quiet refs/heads/unmerged
    run git-branch-remove -C "$repo" --force unmerged
    [ "$status" -eq 0 ]
    git -C "$repo" worktree add -qb occupied "$WORK/occupied"
    run git-branch-remove -C "$repo" --force occupied
    [ "$status" -ne 0 ]
    run git-branch-remove -C "$repo" --force main
    [ "$status" -ne 0 ]
}

@test "remote deletion is explicit, narrowly scoped and honors confirmation and previews" {
    make_remote
    git -C "$repo" branch target
    git -C "$repo" push -q origin refs/heads/target
    git -C "$repo" tag never-push
    git -C "$repo" config remote.origin.mirror true
    git -C "$repo" config push.followTags true
    run git-branch-remove -C "$repo" --remote origin --dry-run target
    [ "$status" -eq 0 ]
    git --git-dir="$WORK/remote.git" show-ref --verify --quiet refs/heads/target
    run bash -c 'printf "n\n" | git-branch-remove -C "$1" --remote origin --confirm target' _ "$repo"
    [ "$status" -eq 0 ]
    git --git-dir="$WORK/remote.git" show-ref --verify --quiet refs/heads/target
    run git-branch-remove -C "$repo" --remote origin target
    [ "$status" -eq 0 ]
    ! git --git-dir="$WORK/remote.git" show-ref --verify --quiet refs/heads/target
    git -C "$repo" show-ref --verify --quiet refs/heads/target
    git --git-dir="$WORK/remote.git" show-ref --verify --quiet refs/heads/main
    ! git --git-dir="$WORK/remote.git" show-ref --verify --quiet refs/tags/never-push
    run git-branch-remove -C "$repo" --remote "$WORK/remote.git" main
    [ "$status" -ne 0 ]
    run git-branch-remove -C "$repo" --remote origin --force main
    [ "$status" -ne 0 ]
}

@test "branch deletion validates refs and reports native remote and local failures" {
    for branch in 'refs/tags/main' 'main~1' '@{-1}' '--all' 'main*'; do
        run git-branch-remove -C "$repo" -- "$branch"
        [ "$status" -ne 0 ]
    done
    run git-branch-remove -C "$repo" missing
    [ "$status" -ne 0 ]
    git -C "$repo" remote add broken "$WORK/missing.git"
    run git-branch-remove -C "$repo" --remote broken target
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not appear to be a git repository"* ]]
}

@test "stash saving is tracked-only by default and reports actual identity or null for no-op" {
    printf 'dirty\n' >> "$repo/file"
    printf 'new\n' > "$repo/untracked"
    printf 'ignored\n' > "$repo/ignored"
    message=$'literal \'message\' $HOME $(not-executed); *\nsecond line'
    run git-stash-save -C "$repo" --message "$message" --json
    [ "$status" -eq 0 ]
    json_is '.objectId|test("^[0-9a-f]{40}$")'
    [ "$(jq -r '.objectId' <<< "$output")" = "$(git -C "$repo" rev-parse refs/stash)" ]
    [[ "$(git -C "$repo" log -1 --format=%B refs/stash)" == *"$message"* ]]
    [ -f "$repo/untracked" ]
    [ -f "$repo/ignored" ]
    [ "$(cat "$repo/file")" = initial ]
    run git-stash-save -C "$repo" --json
    [ "$status" -eq 0 ]
    [ "$output" = null ]
    [ "$(git -C "$repo" stash list | wc -l)" -eq 1 ]
}

@test "stash save distinguishes untracked, ignored and keep-index selections" {
    printf 'staged\n' >> "$repo/file"
    git -C "$repo" add file
    printf 'unstaged\n' >> "$repo/file"
    printf 'new\n' > "$repo/untracked"
    printf 'ignored\n' > "$repo/ignored"
    run git-stash-save -C "$repo" --keep-index --include-untracked --json
    [ "$status" -eq 0 ]
    [ ! -e "$repo/untracked" ]
    [ -e "$repo/ignored" ]
    [ "$(cat "$repo/file")" = $'initial\nstaged' ]
    [ "$(git -C "$repo" show :file)" = $'initial\nstaged' ]
    [ "$(git -C "$repo" show 'stash@{0}:file')" = $'initial\nstaged\nunstaged' ]
    run git-stash-save -C "$repo" --include-ignored --json
    [ "$status" -eq 0 ]
    [ ! -e "$repo/ignored" ]
    run git-stash-save -C "$repo" --include-ignored --include-untracked
    [ "$status" -ne 0 ]
}

@test "stash save previews, refusals and native failures preserve changes" {
    printf 'dirty\n' >> "$repo/file"
    run git-stash-save -C "$repo" --dry-run
    [ "$status" -eq 0 ]
    run bash -c 'printf "n\n" | git-stash-save -C "$1" --confirm' _ "$repo"
    [ "$status" -eq 0 ]
    ! git -C "$repo" show-ref --verify --quiet refs/stash
    : > "$repo/.git/index.lock"
    run git-stash-save -C "$repo" --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"git stash push failed"* ]]
    grep -q dirty "$repo/file"
    ! git -C "$repo" show-ref --verify --quiet refs/stash
}

@test "config setter writes literal empty and special values at isolated scopes" {
    original="$PWD"
    value=$'--literal \'quotes\' "double" $HOME $(touch NOT_EXECUTED); *\nsecond line'
    for scope in local global system; do
        run git-config-set -C "$repo" --scope "$scope" test.literal "$value"
        [ "$status" -eq 0 ]
        [ "$(git -C "$repo" config "--$scope" --get test.literal)" = "$value" ]
        run git-config-set -C "$repo" --scope "$scope" test.empty ''
        [ "$status" -eq 0 ]
        [ "$(git -C "$repo" config "--$scope" --get test.empty)" = '' ]
    done
    [ "$PWD" = "$original" ]
    run git-config-set -C "$WORK" --scope global test.outside yes
    [ "$status" -eq 0 ]
    [ "$(git config --global --get test.outside)" = yes ]
    [ ! -e "$repo/NOT_EXECUTED" ]
}

@test "config setter validates scope and keys and propagates write or multivalue failures" {
    run git-config-set -C "$repo" --scope invalid test.key value
    [ "$status" -ne 0 ]
    run git-config-set -C "$repo" invalid-key value
    [ "$status" -ne 0 ]
    run git-config-set -C "$repo" -- --add value
    [ "$status" -ne 0 ]
    git -C "$repo" config --add test.multi first
    git -C "$repo" config --add test.multi second
    run git-config-set -C "$repo" test.multi replacement
    [ "$status" -ne 0 ]
    [ "$(git -C "$repo" config --get-all test.multi | wc -l)" -eq 2 ]
    : > "$repo/.git/config.lock"
    run git-config-set -C "$repo" test.key value
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not lock config file"* ]]
}

@test "config preview and declined or EOF confirmation never write" {
    run git-config-set -C "$repo" --dry-run test.key value
    [ "$status" -eq 0 ]
    run bash -c 'printf "n\n" | git-config-set -C "$1" --confirm test.key value' _ "$repo"
    [ "$status" -eq 0 ]
    run bash -c 'git-config-set -C "$1" --confirm test.key value </dev/null' _ "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *Declined* ]]
    ! git -C "$repo" config --get test.key
    run bash -c 'printf "yes\n" | git-config-set -C "$1" --confirm test.key value' _ "$repo"
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" config --get test.key)" = value ]
}

@test "stash restore pops selected native entries and removes only that entry" {
    printf 'first\n' > "$repo/file"
    git -C "$repo" stash push -qm first
    first="$(git -C "$repo" rev-parse refs/stash)"
    printf 'second\n' > "$repo/file"
    git -C "$repo" stash push -qm second
    second="$(git -C "$repo" rev-parse refs/stash)"
    run git-stash-restore -C "$repo" --stash 'stash@{1}'
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = first ]
    [ "$(git -C "$repo" rev-parse refs/stash)" = "$second" ]
    [ "$(git -C "$repo" stash list | wc -l)" -eq 1 ]
    [[ "$(git -C "$repo" stash list --format=%H)" != *"$first"* ]]
    git -C "$repo" restore -- file
    run git-stash-restore -C "$repo"
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = second ]
    ! git -C "$repo" show-ref --verify --quiet refs/stash
    run git-stash-restore -C "$repo"
    [ "$status" -ne 0 ]
}

@test "stash conflict preserves the saved entry and surfaces native failure" {
    printf 'stashed\n' > "$repo/file"
    git -C "$repo" stash push -qm conflict
    saved="$(git -C "$repo" rev-parse refs/stash)"
    printf 'committed\n' > "$repo/file"
    git -C "$repo" commit -qam conflicting
    run git-stash-restore -C "$repo"
    [ "$status" -ne 0 ]
    [ "$(git -C "$repo" rev-parse refs/stash)" = "$saved" ]
    [ -n "$(git -C "$repo" ls-files --unmerged)" ]
    [[ "$output" == *CONFLICT* ]]
}

@test "stash restore validates selectors and honors preview and refusal" {
    printf 'stashed\n' > "$repo/file"
    git -C "$repo" stash push -qm saved
    saved="$(git -C "$repo" rev-parse refs/stash)"
    for selector in "$saved" 0 'stash@{01}' 'stash@{-1}' 'stash@{2147483648}' 'stash@{1}~1' '--all'; do
        run git-stash-restore -C "$repo" --stash "$selector"
        [ "$status" -ne 0 ]
    done
    run git-stash-restore -C "$repo" --dry-run
    [ "$status" -eq 0 ]
    run bash -c 'printf "n\n" | git-stash-restore -C "$1" --confirm' _ "$repo"
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" rev-parse refs/stash)" = "$saved" ]
    [ "$(cat "$repo/file")" = initial ]
}

@test "restore defaults to the index and explicit include-index defaults to HEAD" {
    printf 'staged\n' > "$repo/file"
    git -C "$repo" add file
    printf 'unstaged\n' > "$repo/file"
    run git-restore -C "$repo" -- file
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = staged ]
    [ "$(git -C "$repo" show :file)" = staged ]
    run git-restore -C "$repo" --include-index -- file
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = initial ]
    [ "$(git -C "$repo" show :file)" = initial ]
}

@test "restore uses explicit sources without changing the caller location" {
    old="$(git -C "$repo" rev-parse HEAD)"
    printf 'new commit\n' > "$repo/file"
    git -C "$repo" commit -qam second
    original="$PWD"
    run git-restore -C "$repo" --source "$old" -- file
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = initial ]
    [ "$(git -C "$repo" show :file)" = 'new commit' ]
    [ "$PWD" = "$original" ]
    run git-restore -C "$repo" --include-index --source "$old" -- file
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" show :file)" = initial ]
    run git-restore -C "$repo" --source no-such-revision -- file
    [ "$status" -ne 0 ]
}

@test "restore treats spaces, leading dashes and wildcard or magic filenames literally" {
    names=('space name' '-leading' '*.txt' '[ab].txt' ':(glob)*')
    for name in "${names[@]}" other.txt a.txt; do printf 'original\n' > "$repo/$name"; done
    git -C "$repo" add .
    git -C "$repo" commit -qm files
    for name in "${names[@]}" other.txt a.txt; do printf 'modified\n' > "$repo/$name"; done
    run git-restore -C "$repo" -- "${names[@]}"
    [ "$status" -eq 0 ]
    for name in "${names[@]}"; do [ "$(cat "$repo/$name")" = original ]; done
    [ "$(cat "$repo/other.txt")" = modified ]
    [ "$(cat "$repo/a.txt")" = modified ]
}

@test "restore preview, refusal and invalid paths preserve staged and working changes" {
    printf 'staged\n' > "$repo/file"
    git -C "$repo" add file
    printf 'unstaged\n' > "$repo/file"
    run git-restore -C "$repo" --include-index --dry-run -- file
    [ "$status" -eq 0 ]
    run bash -c 'printf "n\n" | git-restore -C "$1" --include-index --confirm -- file' _ "$repo"
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/file")" = unstaged ]
    [ "$(git -C "$repo" show :file)" = staged ]
    run git-restore -C "$repo" --force -- file
    [ "$status" -ne 0 ]
    run git-restore -C "$repo" -- missing
    [ "$status" -ne 0 ]
    run git-restore -C "$repo" -- ''
    [ "$status" -ne 0 ]
}

@test "restore refuses selected unmerged entries even with source and include-index" {
    git -C "$repo" checkout -qb other
    printf 'other\n' > "$repo/file"
    git -C "$repo" commit -qam other
    git -C "$repo" checkout -q main
    printf 'main\n' > "$repo/file"
    git -C "$repo" commit -qam main
    git -C "$repo" merge other >/dev/null 2>&1 || true
    before="$(git -C "$repo" ls-files --unmerged)"
    run git-restore -C "$repo" --source HEAD --include-index -- file
    [ "$status" -ne 0 ]
    [[ "$output" == *"unmerged index entries"* ]]
    [ "$(git -C "$repo" ls-files --unmerged)" = "$before" ]
}

@test "worktree removal now deletes even unmerged local branches by default" {
    make_remote
    git -C "$repo" worktree add -qb feature "$WORK/feature"
    printf 'unmerged\n' > "$WORK/feature/new"
    git -C "$WORK/feature" add .
    git -C "$WORK/feature" commit -qm unmerged
    git -C "$repo" push -q origin feature
    run git-worktree-remove -C "$repo" --path "$WORK/feature"
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/feature" ]
    ! git -C "$repo" show-ref --verify --quiet refs/heads/feature
    git --git-dir="$WORK/remote.git" show-ref --verify --quiet refs/heads/feature
}

@test "worktree removal keep-branch and every legacy false spelling retain branches" {
    options=(--keep-branch --delete-branch=false --delete-branch:0)
    for i in "${!options[@]}"; do
        git -C "$repo" worktree add -qb "feature$i" "$WORK/feature$i"
        run git-worktree-remove -C "$repo" "${options[$i]}" "feature$i"
        [ "$status" -eq 0 ]
        [ ! -e "$WORK/feature$i" ]
        git -C "$repo" show-ref --verify --quiet "refs/heads/feature$i"
    done
    git -C "$repo" worktree add -qb separated "$WORK/separated"
    run git-worktree-remove -C "$repo" --delete-branch false separated
    [ "$status" -eq 0 ]
    git -C "$repo" show-ref --verify --quiet refs/heads/separated
    git -C "$repo" worktree add -qb legacy "$WORK/legacy"
    run git-worktree-remove -C "$repo" --delete-branch=true legacy
    [ "$status" -eq 0 ]
    ! git -C "$repo" show-ref --verify --quiet refs/heads/legacy
}

@test "worktree removal and deletion preview and confirm as separate gates" {
    git -C "$repo" worktree add -qb feature "$WORK/feature"
    run git-worktree-remove -C "$repo" --dry-run feature
    [ "$status" -eq 0 ]
    [[ "$output" == *'What if: Remove worktree'* ]]
    [[ "$output" == *"What if: Delete local branch 'feature'"* ]]
    [ -e "$WORK/feature/.git" ]
    run bash -c 'printf "n\ny\n" | git-worktree-remove -C "$1" --confirm feature' _ "$repo"
    [ "$status" -eq 0 ]
    [ -e "$WORK/feature/.git" ]
    git -C "$repo" show-ref --verify --quiet refs/heads/feature
    [[ "$output" != *"Delete local branch"* ]]
    run bash -c 'printf "y\nn\n" | git-worktree-remove -C "$1" --confirm feature' _ "$repo"
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/feature" ]
    git -C "$repo" show-ref --verify --quiet refs/heads/feature
    git -C "$repo" worktree add -q "$WORK/feature" feature
    run bash -c 'printf "y\ny\n" | git-worktree-remove -C "$1" --confirm feature' _ "$repo"
    [ "$status" -eq 0 ]
    ! git -C "$repo" show-ref --verify --quiet refs/heads/feature
}

@test "worktree removal failures retain branches without force escalation or retry" {
    git -C "$repo" worktree add -qb feature "$WORK/feature"
    printf 'dirty\n' > "$WORK/feature/file"
    run git-worktree-remove -C "$repo" feature
    [ "$status" -ne 0 ]
    git -C "$repo" show-ref --verify --quiet refs/heads/feature
    [ -d "$WORK/feature" ]
    git -C "$repo" worktree lock "$WORK/feature"
    run git-worktree-remove -C "$repo" --force feature
    [ "$status" -ne 0 ]
    git -C "$repo" show-ref --verify --quiet refs/heads/feature
    [ -d "$WORK/feature" ]
    git -C "$repo" worktree unlock "$WORK/feature"
    run git-worktree-remove -C "$repo" --force feature
    [ "$status" -eq 0 ]
    ! git -C "$repo" show-ref --verify --quiet refs/heads/feature
}

@test "detached worktree removal never previews or performs branch deletion" {
    git -C "$repo" worktree add -q --detach "$WORK/detached"
    before="$(git -C "$repo" for-each-ref refs/heads)"
    run git-worktree-remove -C "$repo" --path "$WORK/detached" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *'Delete local branch'* ]]
    run git-worktree-remove -C "$repo" --path "$WORK/detached"
    [ "$status" -eq 0 ]
    [ ! -e "$WORK/detached" ]
    [ "$(git -C "$repo" for-each-ref refs/heads)" = "$before" ]
}

make_update_fixture() {
    make_remote
    local branch next
    for branch in updated failed stashfailed missing inprogress removed skipped; do
        git -C "$repo" branch "$branch"
        git -C "$repo" push -qu origin "$branch"
        git -C "$repo" worktree add -q "$WORK/$branch" "$branch"
    done
    git -C "$repo" worktree add -qb noupstream "$WORK/noupstream"
    next="$(printf 'advance\n' | git --git-dir="$WORK/remote.git" commit-tree 'main^{tree}' -p main)"
    for branch in updated failed stashfailed missing inprogress; do
        git --git-dir="$WORK/remote.git" update-ref "refs/heads/$branch" "$next"
    done
    git -C "$repo" push -q origin --delete removed
    printf 'local\n' > "$WORK/skipped/new"
    git -C "$WORK/skipped" add .
    git -C "$WORK/skipped" commit -qm local
    printf '%s\n' "$next" > "$(git -C "$WORK/inprogress" rev-parse --absolute-git-dir)/MERGE_HEAD"
    printf 'dirty\n' >> "$WORK/stashfailed/file"
    rm -rf -- "$WORK/missing"
    mkdir "$WORK/stubs"
    cat > "$WORK/stubs/git" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *"/failed merge --ff-only "*) echo 'merge failed' >&2; exit 42 ;;
    *"/stashfailed stash push "*) echo 'stash failed' >&2; exit 43 ;;
esac
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WORK/stubs/git"
}

@test "single updater defaults to all statuses and changed-only preserves actionable failures" {
    make_update_fixture
    run bash -c 'PATH="$1:$PATH" git-worktree-update -C "$2" --json 2>"$3"' \
        _ "$WORK/stubs" "$repo" "$WORK/errors"
    [ "$status" -ne 0 ]
    json_is 'map(.status)|sort == ["Current","Failed","InProgress","Missing","NoUpstream","Removed","Skipped","StashFailed","Updated"]'
    grep -q 'stash failed' "$WORK/errors"
    # The synthetic update has an identical tree; rewind only its disposable ref.
    git -C "$WORK/updated" update-ref refs/heads/updated HEAD~1
    run bash -c 'PATH="$1:$PATH" git-worktree-update -C "$2" --changed-only --json 2>"$3"' \
        _ "$WORK/stubs" "$repo" "$WORK/errors"
    [ "$status" -ne 0 ]
    json_is 'map(.status)|sort == ["Failed","Removed","StashFailed","Updated"]'
    grep -q "missing.*$WORK/missing" "$WORK/errors"
    git -C "$WORK/updated" update-ref refs/heads/updated HEAD~1
    run env PATH="$WORK/stubs:$PATH" git-worktree-update -C "$repo" --changed-only
    [ "$status" -ne 0 ]
    [[ "$output" == *Updated* && "$output" == *Failed* && "$output" == *StashFailed* && "$output" == *Removed* ]]
    [[ "$output" != *Current* && "$output" != *NoUpstream* && "$output" != *InProgress* ]]
}

@test "single updater changed-only previews remain visible without changing eligibility or data" {
    make_update_fixture
    git -C "$repo" fetch -q --prune origin
    before="$(git -C "$WORK/updated" rev-parse HEAD)"
    run bash -c 'PATH="$1:$PATH" git-worktree-update -C "$2" --changed-only --dry-run --json 2>"$3"' \
        _ "$WORK/stubs" "$repo" "$WORK/preview"
    [ "$status" -eq 0 ]
    json_is 'map(.status)==["Removed"]'
    grep -q 'What if: Fast-forward' "$WORK/preview"
    [ "$(git -C "$WORK/updated" rev-parse HEAD)" = "$before" ]
    grep -q dirty "$WORK/stashfailed/file"
}

@test "single updater changed-only does not conceal failed fetch diagnostics" {
    git -C "$repo" remote add broken "$WORK/missing-remote.git"
    run git-worktree-update -C "$repo" --changed-only --json
    [ "$status" -ne 0 ]
    [[ "$output" == *'Failed to fetch remotes'* ]]
    [[ "$output" != '[]' ]]
}

@test "changed-worktree display preserves every field at 80 100 120 and 160 columns" {
    fixture="$(jq -n '
        [{organization:"short",repository:"ok",branch:null,status:"Updated",behindBy:1,path:"/short",error:null},
         {organization:("org"+("O"*180)),repository:("repo"+("R"*220)),
          branch:("feature/"+("B"*240)),status:"StashFailed",behindBy:123456789012,
          path:("/long/"+("P"*350)),error:("First diagnostic "+("E"*210)+"\n\nFinal recovery: restore the saved stash explicitly.")}]')"
    for width in 80 100 120 160; do
        run bash -c 'source "$1/lib/git/git-display.sh"; COLUMNS="$2" git_display_changed_worktrees' \
            _ "$REPO_ROOT" "$width" <<< "$fixture"
        [ "$status" -eq 0 ]
        printf '%s\n' "$output" | awk -v width="$width" 'length($0)>width {exit 1}'
        [[ "$output" == *'Status: Updated (behind: 1)'* ]]
        [[ "$output" == *'Status: StashFailed (behind: 123456789012)'* ]]
        [ "$(printf '%s\n' "$output" | grep -c '^Error:')" -eq 1 ]
        for field in organization repository branch path error; do
            label="${field^}:"
            expected="$(jq -r --arg field "$field" '.[1][$field] | gsub("\n";"")' <<< "$fixture")"
            actual="$(printf '%s\n' "$output" | awk -v label="$label" '
                $0 ~ "^[A-Z][a-z]+:" {active=0}
                index($0,label)==1 {if (++count==2 || label=="Error:") {active=1; sub("^[^:]*: ?",""); printf "%s",$0}; next}
                active && /^ +/ {printf "%s",substr($0,length(label)+2)}')"
            [ "$actual" = "$expected" ]
        done
    done
}

@test "bulk updater keeps JSON filtering, previews and explicit table rendering" {
    root="$WORK/repos"
    mkdir -p "$root/acme/widget"
    git clone -q "$repo" "$root/acme/widget/main"
    run git-worktree-update-all --path "$root" --changed-only --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *'Organization: acme'* && "$output" == *'Repository: widget'* ]]
    [[ "$output" == *'Status: WhatIf (behind: 0)'* ]]
    [[ "$output" != *'Error:'* ]]
    run git-worktree-update-all --path "$root" --changed-only --dry-run --table
    [ "$status" -eq 0 ]
    [[ "$output" == *'ORGANIZATION'* && "$output" == *'BEHIND'* && "$output" != *'Organization:'* ]]
    run bash -c 'git-worktree-update-all --path "$1" --changed-only --dry-run --json 2>/dev/null' _ "$root"
    [ "$status" -eq 0 ]
    json_is '.[0]|.status=="WhatIf" and .organization=="acme" and .repository=="widget" and .error==null'
    run git-worktree-update-all --path "$root" --changed-only --json
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
}
