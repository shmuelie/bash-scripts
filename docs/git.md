# Git commands

A bash port of the `Shmuelie.Git` PowerShell module. Every command is an
executable in `bin/`. Add `bin/` to your `PATH` first.

## Commands

| Command | Purpose |
|---|---|
| `git-repo-new` | Clone a URL into a standard `<root>/<org>/<repo>/<branch>` layout (parses GitHub and Azure DevOps URLs) |
| `git-repo-repair` | Conform existing clones and worktrees to that layout |
| `git-sync` | Fetch remotes with pruning and optional per-owner GitHub account selection |
| `git-worktree-list` | List worktrees including bare, detached, locked, and prunable state |
| `git-worktree-current` / `git-worktree-root` | Resolve the worktree for the current directory or the repository root |
| `git-worktree-path` | Compute the path a branch's worktree would use |
| `git-worktree-new` | Create a branch and check it out, optionally at `--worktree-path` |
| `git-worktree-add` | Check out an existing branch, optionally at `--worktree-path` |
| `git-worktree-remove` | Remove a worktree by branch or actual path (optionally deleting its branch) |
| `git-worktree-switch` | Print the path of a worktree selected by branch or path |
| `git-worktree-move` | Move a linked worktree while refusing the main/root worktree |
| `git-worktree-lock` / `git-worktree-unlock` | Lock or unlock a worktree, with optional lock reason |
| `git-worktree-prune` / `git-worktree-repair` | Prune stale administrative entries or repair moved worktree links |
| `git-worktree-update` | Fast-forward every worktree from upstream, skipping in-progress Git operations |
| `git-worktree-update-all` | Discover and update repositories below a root, with filters/concurrency |
| `git-stale-branch` | Find local branches whose upstream branch is gone (`--include-never-pushed` opts into local-only branches) |
| `git-status-summary` | Parse `git status` into a structured summary |
| `git-status-segment` | Render an ANSI-colored prompt segment from the status summary |

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

Status, worktree, sync, stale-branch, and update commands accept
`--path <repository-or-child>` (or `-C` where unambiguous), so callers can
operate on another repository without changing directory. Commands whose
`--path` identifies a worktree use `-C`/`--repository-path` for the containing
repository.

## Completion

`completions/bash/shm-git-completion.bash` and
`completions/zsh/shm-git-completion.zsh` suggest worktree branch names for
`git-worktree-switch`, `git-worktree-remove`, `git-worktree-add`, and the
maintenance/move/lock commands, using substring (not just prefix) matching.
Enable the bash version with:

```bash
source /path/to/completions/bash/shm-git-completion.bash
```

## Examples

```bash
git-repo-new https://github.com/owner/repo
cd "$(git-worktree-new my-feature)"
git-worktree-new --path ../main --worktree-path ../custom my-feature
git-worktree-lock feature/my-feature --reason "long-running environment"
git-worktree-move feature/my-feature ../moved-feature
git-worktree-prune --dry-run --expire now
git-worktree-update --json | jq '.[] | select(.status != "Current")'
git-worktree-update-all --organization shmuelie --changed-only
git-stale-branch | git-worktree-remove --delete-branch
git-stale-branch --include-never-pushed
git-status-summary --string
PS1='$(git-status-segment --ps1 --no-change-counts) \w\$ '
```

Relative `--worktree-path` values for add/new are resolved from the selected
repository; `git-worktree-move` destinations are resolved from the caller's
current directory.

`git-worktree-update` returns `InProgress` with an `operation` value instead of
stashing or merging a worktree during an active merge, rebase, cherry-pick,
revert, or bisect. A worktree directory removed during an update is reported as
`Missing`. With `--check-remote`, a failed remote lookup leaves `NoUpstream`
worktrees unclassified and emits a warning.

`git-stale-branch` treats only configured upstreams marked `[gone]` as stale by
default. `--include-never-pushed` also includes branches with no upstream.
Configured remote lookup failures are errors rather than evidence that every
candidate branch was deleted.

## Bulk updates

`git-worktree-update-all` scans `--path` (default `SOURCE_REPOS`, then cwd),
groups worktrees by organization/repository, and runs updates with `--jobs`
concurrency. `--organization`, `--name`, and `--exclude` accept repeatable
comma-separated glob filters. `--changed-only` flattens updated, removed, or
failed worktrees while retaining repository context; one repository failure
does not stop the remaining work. After all repositories are processed, the
command exits non-zero if any repository failed.

## GitHub accounts

When several accounts are signed in through `gh`, `git-sync` can retry the
account that has access to each GitHub/GHE owner without switching the globally
active account. Tokens are injected only into the Git child process.

```bash
git-sync --github-account github.com/acme=work-user
git-worktree-update --github-account github.com/acme=work-user
git-sync --no-github-account-resolve
```

The mapping and opt-out options are forwarded by `git-worktree-update` and
`git-worktree-update-all`.

## Requirements

- `git` and `jq` on `PATH`.

## JSON output

`git-worktree-list`, `git-sync`, `git-worktree-update`,
`git-worktree-update-all`, `git-stale-branch`, `git-status-summary`, and
`git-repo-repair` accept `--json` for machine-readable output.
