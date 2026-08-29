# Git commands

A bash port of the `Shmuelie.Git` PowerShell module. Every command is an
executable in `bin/`. Add `bin/` to your `PATH` first.

## Commands

| Command | Purpose |
|---|---|
| `git-repo-new` | Clone a URL into a standard `<root>/<org>/<repo>/<branch>` layout (parses GitHub and Azure DevOps URLs) |
| `git-repo-repair` | Conform existing clones and worktrees to that layout |
| `git-sync` | Fetch all remotes with pruning, reporting ref changes |
| `git-worktree-list` | List worktrees for the current repository |
| `git-worktree-current` / `git-worktree-root` | Resolve the worktree for the current directory or the repository root |
| `git-worktree-path` | Compute the path a branch's worktree would use |
| `git-worktree-new` | Create a branch and check it out to a worktree |
| `git-worktree-add` | Check out an existing branch to a worktree |
| `git-worktree-remove` | Remove a worktree (optionally deleting its branch) |
| `git-worktree-switch` | Print the path of a worktree by branch name (use with `cd`) |
| `git-worktree-update` | Fast-forward every worktree from upstream, skipping in-progress Git operations |
| `git-stale-branch` | Find local branches whose upstream branch is gone (`--include-never-pushed` opts into local-only branches) |
| `git-status-summary` | Parse `git status` into a structured summary |

## Directory changes

A child process cannot change its parent shell's working directory, so commands
that would `Set-Location` in PowerShell instead print the target path:

```bash
cd "$(git-worktree-switch main)"
cd "$(git-worktree-new my-feature)"
cd "$(git-repo-new https://github.com/owner/repo)"
```

## Layout

`git-repo-new` clones into `<root>/<org>/<repo>/<branch>`, where `<root>` comes
from `--root` or the `SOURCE_REPOS` environment variable. It recognizes GitHub
and Azure DevOps HTTPS and SSH URLs, and detects the remote default branch when
`--branch` is not given.

## Completion

`completions/bash/shm-git-completion.bash` and
`completions/zsh/shm-git-completion.zsh` suggest worktree branch names for
`git-worktree-switch`, `git-worktree-remove`, and `git-worktree-add`, using
substring (not just prefix) matching. Enable the bash version with:

```bash
source /path/to/completions/bash/shm-git-completion.bash
```

## Examples

```bash
git-repo-new https://github.com/owner/repo
cd "$(git-worktree-new my-feature)"
git-worktree-update --json | jq '.[] | select(.status != "Current")'
git-stale-branch | git-worktree-remove --delete-branch
git-stale-branch --include-never-pushed
git-status-summary --string
```

`git-worktree-update` returns `InProgress` with an `operation` value instead of
stashing or merging a worktree during an active merge, rebase, cherry-pick,
revert, or bisect. A worktree directory removed during an update is reported as
`Missing`. With `--check-remote`, a failed remote lookup leaves `NoUpstream`
worktrees unclassified and emits a warning.

`git-stale-branch` treats only configured upstreams marked `[gone]` as stale by
default. `--include-never-pushed` also includes branches with no upstream.
Configured remote lookup failures are errors rather than evidence that every
candidate branch was deleted.

## Requirements

- `git` and `jq` on `PATH`.

## JSON output

`git-worktree-list`, `git-sync`, `git-worktree-update`, `git-stale-branch`,
`git-status-summary`, and `git-repo-repair` accept `--json` for
machine-readable output.
