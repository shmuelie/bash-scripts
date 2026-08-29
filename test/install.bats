#!/usr/bin/env bats
# install.bats — tests for install.sh (symlink + path methods, uninstall).
# Runs against temp --prefix/--rc so real config is never touched.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WORK="$(mktemp -d)"; export WORK
    PREFIX="$WORK/bin"; RC="$WORK/rc"
}
teardown() { rm -rf "$WORK"; }

@test "symlink install links every bin command" {
    run "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC"
    [ "$status" -eq 0 ]
    linked="$(find "$PREFIX" -maxdepth 1 -type l | wc -l)"
    binned="$(find "$REPO_ROOT/bin" -maxdepth 1 -type f | wc -l)"
    [ "$linked" -eq "$binned" ]
}

@test "a symlinked command resolves lib and runs" {
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" >/dev/null
    run "$PREFIX/git-worktree-list" --help
    [ "$status" -eq 0 ]
}

@test "symlink install adds a completions rc block" {
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" >/dev/null
    grep -qF '# >>> bash-scripts >>>' "$RC"
    grep -qF 'shm-git-completion.bash' "$RC"
}

@test "re-running does not duplicate the rc block" {
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" >/dev/null
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" >/dev/null
    run grep -cF '# >>> bash-scripts >>>' "$RC"
    [ "$output" = "1" ]
}

@test "path method writes a PATH export instead of symlinks" {
    run "$REPO_ROOT/install.sh" --method path --prefix "$PREFIX" --rc "$RC"
    [ "$status" -eq 0 ]
    grep -qF "export PATH=\"$REPO_ROOT/bin:\$PATH\"" "$RC"
    [ ! -d "$PREFIX" ]
}

@test "uninstall removes symlinks and the rc block" {
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" >/dev/null
    run "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" --uninstall
    [ "$status" -eq 0 ]
    [ "$(find "$PREFIX" -maxdepth 1 -type l | wc -l)" -eq 0 ]
    ! grep -qF 'bash-scripts' "$RC"
}

@test "uninstall only removes symlinks that point into this repo" {
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" >/dev/null
    ln -s /bin/true "$PREFIX/unrelated-link"
    "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" --uninstall >/dev/null
    [ -L "$PREFIX/unrelated-link" ]
}

@test "--no-completions skips the rc block on symlink install" {
    run "$REPO_ROOT/install.sh" --method symlink --prefix "$PREFIX" --rc "$RC" --no-completions
    [ "$status" -eq 0 ]
    [ ! -f "$RC" ] || ! grep -qF 'bash-scripts' "$RC"
}

@test "--update and --uninstall together are rejected" {
    run "$REPO_ROOT/install.sh" --update --uninstall
    [ "$status" -ne 0 ]
    [[ "$output" == *"not both"* ]]
}

@test "--update fast-forwards the clone and re-links" {
    # Build a standalone seed repo (CI checks out a shallow detached HEAD).
    mkdir -p "$WORK/seed"
    git -C "$REPO_ROOT" archive HEAD | tar -x -C "$WORK/seed"
    git -C "$WORK/seed" init --quiet --initial-branch=main
    git -C "$WORK/seed" config user.email t@e.com
    git -C "$WORK/seed" config user.name Tester
    git -C "$WORK/seed" add .
    git -C "$WORK/seed" commit --quiet -m seed
    git clone --quiet --bare "$WORK/seed" "$WORK/origin.git"
    git clone --quiet "$WORK/origin.git" "$WORK/clone"
    git -C "$WORK/clone" config user.email t@e.com
    git -C "$WORK/clone" config user.name Tester
    # Exercise the working-tree installer (its --update may be uncommitted).
    cp "$REPO_ROOT/install.sh" "$WORK/clone/install.sh"

    # Second clone adds a new command and pushes it to origin.
    git clone --quiet "$WORK/origin.git" "$WORK/pusher"
    git -C "$WORK/pusher" config user.email t@e.com
    git -C "$WORK/pusher" config user.name Tester
    printf '#!/usr/bin/env bash\necho hi\n' > "$WORK/pusher/bin/brand-new-cmd"
    chmod +x "$WORK/pusher/bin/brand-new-cmd"
    git -C "$WORK/pusher" add bin/brand-new-cmd
    git -C "$WORK/pusher" commit --quiet -m "add brand-new-cmd"
    git -C "$WORK/pusher" push --quiet origin HEAD:main

    before="$(git -C "$WORK/clone" rev-parse HEAD)"
    run "$WORK/clone/install.sh" --update --prefix "$PREFIX" --rc "$RC"
    [ "$status" -eq 0 ]
    after="$(git -C "$WORK/clone" rev-parse HEAD)"
    [ "$before" != "$after" ]
    # The newly pulled command is now symlinked.
    [ -L "$PREFIX/brand-new-cmd" ]
}
