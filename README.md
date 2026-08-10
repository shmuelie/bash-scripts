# bash-scripts

[![Validate scripts](https://github.com/shmuelie/bash-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/shmuelie/bash-scripts/actions/workflows/ci.yml)

A bash port of the [Shmuelie PowerShell modules](https://github.com/shmuelie/powershell-modules).

The PowerShell project ships four modules for Git, GitHub Copilot CLI, Node.js,
and general developer tooling. This repository reimplements those commands as
plain bash scripts that run anywhere bash, `git`, and `jq` are available.

## Layout

```
bin/          Executable commands (kebab-case, e.g. git-worktree-new)
lib/          Sourceable helper libraries (common.sh + per-area helpers)
completions/  bash and zsh completion for the worktree commands
build/        Lint, public-content scan, and test runner
test/         bats-core test suites
```

Add `bin/` to your `PATH`:

```bash
export PATH="/path/to/bash-scripts/bin:$PATH"
```

## Modules

| Area | Status | Focus |
|---|---|---|
| [Git](docs/git.md) | Ported | Worktrees, repo layout, status, sync, stale branches, completion |
| [Copilot](docs/copilot.md) | Ported | Copilot CLI launcher, sessions, plugins, marketplaces, MCP |
| [Node](docs/node.md) | Ported | Node/nvm versions, npm packages, Azure DevOps npm credentials |
| [Utilities](docs/utilities.md) | Ported | .NET, Python, VS Code, terminal, services, diagnostics |

## Conventions

- **Commands are kebab-case executables** in `bin/` (e.g. `git-worktree-new`).
- **`--dry-run` / `--whatif`** previews any state-changing command (the bash
  equivalent of PowerShell's `-WhatIf`).
- **`--json`** emits machine-readable output where a command supports it;
  otherwise a human-readable table or summary is printed.
- Commands that would change the shell's directory (like `Set-Location` in
  PowerShell) instead **print the target path**, so you can use them with `cd`:

  ```bash
  cd "$(git-worktree-switch main)"
  cd "$(git-worktree-new my-feature)"
  ```

## Requirements

- `bash` 4+, `git`, and `jq`.
- Optional: `fzf` for nicer interactive pickers (falls back to `select`).
- `node` for the Copilot session-maintenance subcommands (always present where
  the Copilot CLI runs).

## Development

```bash
./build/test.sh     # syntax check + shellcheck + public-content scan + bats
./build/lint.sh     # shellcheck only
./build/scan.sh     # public-content policy scan only
```

Requires `shellcheck`, `jq`, and `bats-core`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
