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

## Global session selection

`copilot-session select` searches all recorded sessions, filters by
`--id`, `--repository`, or `--branch` globs, and resumes from the selected
session's recorded directory:

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
Commands that rewrite existing files create `.bak` copies unless
`--no-backup` is supplied.

All destructive session operations resolve IDs through a canonical direct-child
guard under `COPILOT_HOME/session-state`; path-like IDs and symlink escapes are
rejected. Failed merges clean their partial destination and preserve sources.

## Requirements

- `copilot` and `jq` on `PATH`.
- `node` for the session-maintenance subcommands.
