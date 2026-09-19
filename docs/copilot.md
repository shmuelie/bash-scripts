# Copilot commands

A bash port of the `Shmuelie.Copilot` PowerShell module. Wraps the public
`copilot` CLI and reads `~/.copilot` session state. Every command is an
executable in `bin/`.

## Commands

| Area | Command |
|---|---|
| Launcher | `start-copilot`, `copilot-launch-plan` |
| Sessions | `copilot-session list/select/resume/rename/remove` |
| Session maintenance | `copilot-session-maintenance merge/compress/repair-events` |
| Plugins | `copilot-plugin list/install/update/uninstall` |
| Marketplaces | `copilot-marketplace list/add/remove/browse` |
| MCP servers | `copilot-mcp list/add/remove` |

## start-copilot

Wraps `copilot` and adds:

- **Automatic session resume** for the current folder — a single session
  resumes automatically, multiple show a picker, and a lone named session
  auto-resumes. Control it with `--no-resume`, `--resume-latest`,
  `--resume-session <id>`, `--no-auto-resume`, and `--include-unnamed`.
  An explicit `--session-id` or launcher `--dry-run` suppresses automatic
  resume and the picker; `--resume-session` remains explicit and takes priority.
- **Sensible defaults** (`--allow-all --experimental`), each disablable with
  `--no-allow-all` / `--no-experimental`.
- **Approval/output controls** — `--assisted-approval`,
  `--allow-all-tools` (suppresses the broader default `--allow-all`), and
  `--usage-output-file <path>`.
- **Default deny rules** for destructive git operations (force push, hard
  reset, rebase, amend, `git pull`, and similar); disable with
  `--no-default-deny-tools`.
- **Autopilot** when a prompt is provided; interactive otherwise.
- **`--passthru`** prints the resolved launch plan without launching.
  `copilot-launch-plan` exposes the same plan directly (add `--json`).
- **`update` / `help`** pass straight through to the executable.

```bash
start-copilot "Add unit tests for the auth module"
start-copilot --resume-latest
start-copilot --no-resume --whatif            # preview the command line
copilot-launch-plan --no-resume --json        # inspect the built args
start-copilot "fix" -- --model claude-opus-4.7 --reasoning-effort high
```

### Argument contract

`start-copilot` recognizes its own resume/permission/MCP flags plus a few common
copilot value-flags (`--model`, `--reasoning-effort`, `--agent`, `--mode`,
`--context`, `--add-dir`, `--log-level`, `--output-format`, `--session-id`,
`--name`, `-C`/`--change-dir`, `--plan`). A single bare argument is the autopilot
**prompt**. Any other copilot flags go after `--`, which is forwarded verbatim.

### MCP autoConnect policy

`start-copilot` reads the `autoConnect` field of each server in
`~/.copilot/mcp-config.json` and decides which to disable for the current
directory:

| `autoConnect` value | Behavior |
|---|---|
| `true` or omitted | Always enabled. |
| `false` | Left to the CLI's native lazy handling. |
| `["glob", ...]` | Enabled only when the current directory matches a glob. |

Use `--enable-mcp-server <name>` to force one on and forward the CLI's native
enable flag, or `--disable-mcp-server <name>` to force one off.

### Managed MCP configuration

`copilot-mcp add/remove` refuses native mutation when
`$COPILOT_HOME/mcp-config.json` (default `~/.copilot/mcp-config.json`) is a
symbolic link, including a dangling link. Manage the target directly instead;
the native CLI may replace the link during an atomic save. Ordinary or absent
configuration files retain native behavior. `--dry-run`/`--whatif` previews do
not inspect or change the target; removal accepts the preview flag before or
after the server name.

## Session discovery and filtering

`copilot-session list` defaults to the current directory; `--all` is explicit
global discovery and `--id` remains an exact, directory-independent lookup.
List and select share case-insensitive `--repository`, `--branch`, `--cwd`,
and `--summary` glob filters, combined with AND. An explicit `--cwd` replaces
the implicit current-directory scope and matches recorded paths literally
(without resolving or normalizing them). Repository/branch/summary filters
alone do not expand local discovery. Missing repository, branch, or directory
metadata never matches an explicit filter, even `*`. Summary means the displayed
name, then legacy summary, then `(no summary)`.

`--updated-before` accepts an ISO 8601 date or timestamp. `Z` or an explicit
`+HH:MM`/`-HH:MM` offset identifies an instant; omitted offsets use the local
timezone and date-only input means local midnight. `--older-than` takes a
positive integer (1-999999999) with `s`, `m`, `h`, `d`, or `w`, such as `30d`.
Days mean elapsed 24-hour periods, not calendar days. Both age cutoffs are
exclusive and combine with AND; the age clock is sampled once per invocation.
Missing/invalid update times never match age filters (invalid values warn);
creation and filesystem times are never substituted. Sorting compares normalized
update instants, newest first, with undated sessions last.

```bash
copilot-session list --all --repository 'owner/*' --branch 'feature/*' --json
copilot-session list --cwd '/work/*' --summary '*cleanup*' --older-than 30d --json
copilot-session list --all --updated-before '2026-08-01T00:00:00Z' --json |
  jq -r '.[].id' |
  while IFS= read -r id; do copilot-session remove "$id" --dry-run; done
```

Discovery never deletes anything. Removal remains a separate explicit,
previewable operation and revalidates each session ID against the session root.

## Global session selection

`copilot-session select` searches all recorded sessions, filters by
the shared metadata/age filters plus an `--id` glob, and resumes from the
selected session's recorded directory. `--first` limits newest-first candidates
only after all filters have matched:

```bash
copilot-session select
copilot-session select --repository 'shmuelie/*' --branch main --first 1
copilot-session select --stay-in-directory "continue" -- --model fast
copilot-session select --dry-run --first 1
```

Multiple matches use the configured fzf/console picker. Dry-run requires the
filters or `--first 1` to resolve exactly one session and never opens a picker.

## Directory changes

`start-copilot` runs in place. `copilot-session resume` execs `copilot`
directly.

## Session maintenance

The event-stream algorithms (relocating orphaned tool events, synthesizing
missing tool completions, compacting, and merging) are implemented in
`lib/copilot/session-maintenance.js` and run under Node, which is always present
where the Copilot CLI runs.

Workspace scalar fields are decoded from plain, single-line or multiline
quoted, literal-block, and folded-block YAML. Rename and merge operations safely
quote updated values while preserving unrelated workspace metadata.

```bash
copilot-session list --json
copilot-session-maintenance repair-events <id>
copilot-session-maintenance compress <id> --keep 10
copilot-session-maintenance merge <id1> <id2> --remove-source
```

`--keep` must be a positive integer. Repair, compress, and merge drop malformed
or truncated JSONL lines when a valid session remains and report the count.
Invalid empty-ID records and unknown-model tool completions are filtered before
relocation, so out-of-order malformed completions cannot reappear after repair.
Valid raw start/completion records retain their payloads.
Commands that rewrite existing files create `.bak` copies unless
`--no-backup` is supplied.

All destructive session operations resolve IDs through a canonical direct-child
guard under `COPILOT_HOME/session-state`; path-like IDs and symlink escapes are
rejected. Failed merges clean their partial destination and preserve sources.
Merge preflights files, research, and rewind artifacts before creating the
destination. Differing contents, incompatible case-only paths, file/directory
conflicts, symbolic links (including dangling links), and special files abort
without removing sources. Overlapping regular files require matching SHA-256
hashes. Hidden files and nested backup directories are retained, and copied
contents are verified before optional source removal. Preview skips artifact
inspection and copying. Merge inactive sessions only; concurrent source changes
and rollback of partially completed source deletion are not supported.

Checkpoint bodies use the same collision and SHA-256 checks, including hidden,
nested, and unindexed files. Only the root `checkpoints/index.md` is regenerated.
Its supported format is a plain three-column `# | Title | File` Markdown table:
numbers are reassigned, while titles and relative file references are retained.
Markdown links, absolute/traversing paths, missing bodies, linked paths, and
non-file bodies are rejected. The generated index and all body copies are read
back and verified before source removal; nested `index.md` files remain ordinary
checkpoint bodies.

## Requirements

- `copilot` and `jq` on `PATH`.
- `node` for the session-maintenance subcommands.
