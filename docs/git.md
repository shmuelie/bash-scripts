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
| `git-worktree-remove` | Remove a worktree and its local branch by default (`--keep-branch` opts out) |
| `git-worktree-switch` | Print the path of a worktree selected by branch or path |
| `git-worktree-move` | Move a linked worktree while refusing the main/root worktree |
| `git-worktree-lock` / `git-worktree-unlock` | Lock or unlock a worktree, with optional lock reason |
| `git-worktree-prune` / `git-worktree-repair` | Prune stale administrative entries or repair moved worktree links |
| `git-worktree-update` | Fast-forward every worktree from upstream, skipping in-progress Git operations |
| `git-worktree-update-all` | Discover and update repositories below a root, with filters/concurrency |
| `git-stale-branch` | Find local branches whose upstream branch is gone (`--include-never-pushed` opts into local-only branches) |
| `git-status-summary` | Parse `git status` into a structured summary |
| `git-status-segment` | Render an ANSI-colored prompt segment from the status summary |
| `git-branch-list` | Inspect local and cached remote branches, tracking counts and symbolic refs |
| `git-tag-list` | Inspect annotated/lightweight tags with exact or wildcard name filters |
| `git-branch-switch` | Switch local branches, explicitly create/track branches, optionally discard changes |
| `git-branch-remove` | Delete merged local branches, or explicitly delete on a configured remote |
| `git-stash-save` / `git-stash-restore` | Save changes and restore them with native stash-pop conflict protection |
| `git-config-set` | Set a literal Git configuration key/value at local, global or system scope |
| `git-restore` | Restore literal files from the index, or explicitly include the index/source revision |

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
git-worktree-update --changed-only --json
git-worktree-update-all --organization shmuelie --changed-only
git-stale-branch | git-worktree-remove
git-stale-branch --include-never-pushed
git-status-summary --string
PS1='$(git-status-segment --ps1 --no-change-counts) \w\$ '
```

## Branches and tags

`git-branch-list` includes both local branches and cached remote-tracking refs;
`--local` and `--remote` select either kind (both flags include both).
`--json` emits `branch`, `refName`, `current`, `commit`, `upstream`, `aheadBy`,
`behindBy`, `upstreamGone`, `symbolicTarget`, `isRemote`, `subject` and
`repositoryPath`. Ahead/behind counts are null without an upstream or when it
is gone. Detached HEAD marks no branch current; unborn branches have no ref
and therefore no row.

`git-tag-list --name 'v1.*' --name stable --json` filters full tag names using
case-sensitive shell globs, without duplicate results. JSON includes `name`,
`reference`, `objectId`, `objectType`, `isAnnotated`, fully peeled
`targetObjectId`/`targetObjectType`, `targetCommit`, `subject`, `annotation`,
`taggerDate`, `creatorDate` and `repositoryPath`. A blob/tree target has a null
`targetCommit`; lightweight tags have a null `annotation`. Annotated messages
retain multiline contents, whitespace and signatures. Lightweight commit
`creatorDate` is the commit's committer date, not a tag creation date.

Both inspection commands accept `--path`/`-C`, including bare repositories and
subdirectories, without changing directory. They never fetch (including lazy
partial-clone fetches), and distinguish empty results (`[]`) from Git failures.

## Branch, stash, configuration and file changes

The commands below accept `--path`/`-C`, `--dry-run`/`--whatif`, and opt-in
`--confirm`. Explicit confirmation accepts only `y`/`yes` (case-insensitive);
declines and EOF leave state unchanged. Previews never prompt. Without
`--confirm`, the existing noninteractive command convention applies. Native
Git failures remain nonzero exits; force options never bypass confirmation.

```bash
git-branch-switch --create feature/new
git-branch-switch --track origin/feature/existing
git-branch-switch main --discard-changes --dry-run
git-branch-remove feature/merged --confirm
git-branch-remove feature/abandoned --force
git-branch-remove feature/finished --remote origin --confirm
git-stash-save --include-untracked --message 'Paused work' --json
git-stash-restore --stash 'stash@{1}' --confirm
git-config-set --scope local user.name 'Example Developer'
git-config-set --scope global core.editor 'code --wait'
git-restore -- 'file with spaces' '*.literal'
git-restore --include-index --source HEAD~1 -- file.txt
```

Branch switching requires an existing local branch by default: it does not
guess a remote. `--create` creates at HEAD without tracking; `--track` creates
from an explicit cached remote branch. They are mutually exclusive.
`--discard-changes` (alias `--force`) can discard staged/unstaged changes and
obstructing untracked files, but never resets an existing branch or overrides
Git's checked-out-worktree protection.

Standalone branch removal uses `git branch -d`; `--force` explicitly permits
unmerged local deletion with `-D`. `--remote <configured-name>` instead deletes
only that remote's `refs/heads/<branch>`, never the local branch. It cannot be
combined with `--force`, and does not allow a URL/path as a remote name.

Stash saving covers tracked files by default. `--keep-index` leaves staged
changes checked out; `--include-untracked` additionally saves untracked files;
`--include-ignored`/`--all` includes both untracked and ignored files. The last
two modes are mutually exclusive. Messages are literal arguments; whitespace-only
messages use Git's default. JSON is an object with `objectId`, `subject`, and
`repositoryPath` only when a new stash was created, otherwise `null`.
Restoring uses native `git stash pop`, defaulting to `stash@{0}`. Explicit
selectors must be canonical `stash@{n}` with a nonnegative 32-bit index, not
object IDs. A conflict/failure retains the entry but can leave partial changes
and unmerged files; no automatic apply/drop retry is attempted. Avoid concurrent
stash writers in the repository, including other worktrees.

Configuration setting defaults to `--scope local`; `global`/`system` also work
outside repositories. Put options before the key/value. Values can be empty
or contain quotes, leading dashes and newlines; they are never evaluated.
Git reports invalid keys, multiple existing values and write failures.

File restoration defaults to **working-tree-only from the index**, preserving
staged changes. `--include-index` restores both index and working tree from
HEAD. `--source` overrides either source default with a local tree-ish.
Files after `--` are literal, including leading dashes and Git wildcard/pathspec
characters; quote them against shell expansion. Directories select tracked
descendants. Unmerged selected paths are refused even with an explicit source.
Native multi-path failures may leave partial changes; no rollback is implied.

## Worktree removal migration

**Breaking default:** `git-worktree-remove` now deletes the backing local branch
after successful removal, using **`git branch -D` even for unmerged branches**.
Use `--keep-branch` to retain the previous default. Legacy `--delete-branch`
remains accepted, including explicit false values (`--delete-branch=false`,
`--delete-branch false`, or `--delete-branch:0`; true/false and 1/0 are accepted).
`--keep-branch` wins when combined with a legacy flag.

Removal and branch deletion have separate preview and `--confirm` gates.
Declining/failing removal never deletes the branch; declining the second
confirmation leaves the branch after removing the worktree. Detached targets
never delete a branch, and remote branches remain untouched. `--force` is passed
to Git once; there is no escalation, retry or process termination. For batch
stdin branch input, omit `--confirm` or invoke each explicit target separately.
This forceful backing-branch cleanup differs deliberately from the merged-only
default of standalone `git-branch-remove`.

Relative `--worktree-path` values for add/new are resolved from the selected
repository; `git-worktree-move` destinations are resolved from the caller's
current directory.

`git-worktree-update` returns `InProgress` with an `operation` value instead of
stashing or merging a worktree during an active merge, rebase, cherry-pick,
revert, or bisect. A worktree directory removed during an update is reported as
`Missing`. With `--check-remote`, a failed remote lookup leaves `NoUpstream`
worktrees unclassified and emits a warning.

`git-worktree-update --changed-only` filters output to `Updated`, `Removed`,
`Failed` and `StashFailed` without changing which worktrees are updated. Normal
output is unchanged without the flag. Previews remain on stderr; a filtered-out
`Missing` result still produces an explicit error and a nonzero exit.

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

Changed-only human output defaults to wrapped multiline details containing
organization, repository, branch, status/behind-count, path and nonempty errors.
Long unbroken values and multiline diagnostics are retained. Width comes from
`COLUMNS`, then the terminal, with an 80-column fallback. `--changed-only --table`
selects the former wide overview; `--json` retains the unchanged structured
result. To inspect previously captured JSON at full detail, use
`jq '.[] | {organization,repository,branch,status,behindBy,path,error}'`.

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
`git-repo-repair`, `git-branch-list`, `git-tag-list`, and `git-stash-save`
accept `--json` for machine-readable output.
