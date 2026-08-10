# Copilot instructions for bash-scripts

This repo is a **bash port of the PowerShell modules at
`shmuelie/powershell-modules`** (Git, GitHub Copilot CLI, Node.js, and general
dev tooling). When porting or changing a command, match the original cmdlet's
behavior; the source module name is cited in each script's header comment.

## Build, test, lint

```bash
./build/test.sh    # syntax check + shellcheck + public-content scan + bats suite
./build/lint.sh    # shellcheck only (bin/, lib/*.sh, completions/bash)
./build/scan.sh    # public-content policy scan + broken-link check
bats test/git.bats                          # one suite
bats test/git.bats --filter 'worktree'      # one test by name substring
```

Requires `shellcheck`, `jq`, `bats-core`; tests configure a temp git repo, so a
global git identity must be set. CI (`.github/workflows/ci.yml`) runs
`./build/test.sh` on Ubuntu.

## Architecture

- **`bin/<area>-<verb>`** — every command is a small kebab-case executable
  (e.g. `git-worktree-new`, `copilot-session`, `dotnet-tool`). Multi-operation
  commands take a subcommand as `$1` (e.g. `copilot-session list`).
- **`lib/`** — sourceable logic. Every command sources `lib/common.sh` first,
  then its area helper (`lib/git/git-common.sh`, `lib/copilot/copilot-common.sh`,
  `lib/copilot/launch-plan.sh`, `lib/node/nvm-common.sh`). Put shared/testable
  logic in `lib/`, keep `bin/` scripts thin.
- **`lib/copilot/session-maintenance.js`** — the one intentional exception:
  event-stream surgery (merge/compress/repair) runs under Node because it needs
  stateful JSONL reordering. Keep it **Node v12 compatible** (no `??`, `?.`,
  `||=`, `crypto.randomUUID`, or `fs.cpSync` — helpers `uuidv4`/`copyRecursive`
  exist for the last two).
- `completions/` bash+zsh completion; `docs/<area>.md` per-module reference.

## Conventions (specific to this repo)

- **Every `bin/` script** starts with:
  `set -euo pipefail`, resolves the repo root via
  `_SHM_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"`,
  then sources `lib/common.sh` and its area lib.
- **PowerShell → bash mappings** (keep these consistent):
  - `-WhatIf`/`SupportsShouldProcess` → `--dry-run`/`--whatif`, gated with
    `should_process "<description>" || exit 0` (from `common.sh`).
  - Typed pipeline objects → `--json` (built with `jq`) plus a human table.
  - `Set-Location`/`Push-Location` → **print the target path to stdout** so the
    caller can `cd "$(...)"`; a child process cannot change the parent shell.
  - `Write-Error`/`Write-Verbose`/`Write-Warning` → `die`/`log_verbose`/`log_warn`.
- **`SHM_FS=$'\x1f'`** is the internal field separator for structured rows in the
  Copilot commands — **not tab**. Tab is IFS-whitespace, so `IFS=$'\t' read`
  collapses empty middle fields and shifts columns. Use `SHM_FS` (and jq
  `split("\u001f")`) wherever a row may contain empty fields.
- **jq nullable fields**: use `if .=="" then null else . end` (often defined as
  `def nz`), never `select(.!="")` — `select` yields `empty`, which propagates
  and voids the entire surrounding object.
- **Glob-match `case`/`[[ ]]`** that intentionally mirrors PowerShell `-like`
  (unquoted RHS) carries `# shellcheck disable=SC2053`; TSV/row `read` loops that
  don't use every field carry `# shellcheck disable=SC2034`. Lint must stay
  clean — prefer a scoped `disable` with a reason over leaving warnings.
- **Windows-only source commands** are re-implemented for Linux, not stubbed:
  services→`systemctl`, installed apps→dpkg/rpm/flatpak/snap, WPR→`perf`,
  nvm-windows→`nvm.sh` (sourced; note `node-version use` only affects the
  invoking process).
- **`COPILOT_HOME`** overrides `~/.copilot` (used by tests); prefer such env
  overrides over hardcoded paths so commands stay testable.

## Contribution notes

- Add a command: new `bin/<area>-<verb>`, `chmod +x`, shared logic in `lib/`,
  a bats test in `test/<area>.bats`, update the `docs/<area>.md` table and the
  `[Unreleased]` section of `CHANGELOG.md` (scan enforces `[Unreleased]`).
- This repo is public-distribution: no internal endpoints, org-specific systems,
  or credentials (`build/scan.sh` enforces forbidden markers). Prefer flags and
  env vars over hardcoded hosts/feeds.
