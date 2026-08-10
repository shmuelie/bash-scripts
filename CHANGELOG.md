# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Foundation: repository scaffolding, `lib/common.sh` shared helpers
  (logging, dry-run/ShouldProcess, JSON, dependency checks, fzf/`select`
  picker), `build/` lint + public-content scan + test runner, and CI.
- Git module (`bin/git-*`), a bash port of `Shmuelie.Git`:
  - `git-repo-new` — clone into the `<root>/<org>/<repo>/<branch>` layout,
    parsing GitHub and Azure DevOps URLs.
  - `git-repo-repair` — conform existing clones and worktrees to that layout.
  - `git-sync` — fetch all remotes with pruning and report ref changes,
    restoring tracking config on pruned branches for `[gone]` detection.
  - `git-worktree-list`, `git-worktree-current`, `git-worktree-root`,
    `git-worktree-path`, `git-worktree-new`, `git-worktree-add`,
    `git-worktree-remove`, `git-worktree-switch` — worktree lifecycle.
  - `git-worktree-update` — fast-forward every worktree from upstream.
  - `git-stale-branch` — find local branches whose upstream is gone, with
    optional Azure DevOps PR status.
  - `git-status-summary` — parse `git status` into a structured summary.
  - bash and zsh completion suggesting worktree branch names (substring match),
    replacing the compiled PSReadLine predictor.
- Copilot module (`bin/copilot-*`, `bin/start-copilot`), a bash port of
  `Shmuelie.Copilot`:
  - `start-copilot` and `copilot-launch-plan` — the shared launcher core with
    automatic session resume, default `--allow-all --experimental`, the
    destructive-git deny-tool set, MCP `autoConnect` glob policy, and
    `--passthru`/`--json` plan inspection.
  - `copilot-session list/resume/rename/remove` — session CRUD over
    `~/.copilot/session-state`.
  - `copilot-session-maintenance merge/compress/repair-events` — event-stream
    maintenance (Node helper).
  - `copilot-plugin`, `copilot-marketplace`, `copilot-mcp` — wrappers over the
    `copilot` CLI.
- Node module (`bin/node-*`, `bin/nvm-config`, `bin/npm-package`,
  `bin/ado-npm-token`), a bash port of `Shmuelie.Node` re-targeted to `nvm.sh`:
  Node version/alias management, npm package list/update, and an
  `ado-npm-token` that prints an `export` line for the refreshed token.
- Utilities module (`bin/*`), a bash port of `Shmuelie.Utilities`:
  - Cross-platform: `is-elevated`, `in-location`, `repair-global-json`,
    `reset-terminal`, `dotnet-tool`, `pip-package`, `uv-package`, `vscode-ext`,
    `start-vscode`, `vscode-chat`.
  - Sourceable shell helpers in `lib/utils/shell-integration.sh`
    (`shm_global_constant`, `shm_prepend_path`, `shm_session_title`, ...).
  - Windows-only commands re-implemented for Linux: `service-process`
    (systemd), `installed-apps` (dpkg/rpm/flatpak/snap), `perf-record` (perf),
    and `terminal-config`.
