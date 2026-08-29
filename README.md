# bash-scripts

[![Validate scripts](https://github.com/shmuelie/bash-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/shmuelie/bash-scripts/actions/workflows/ci.yml)

A bash port of the [Shmuelie PowerShell modules](https://github.com/shmuelie/powershell-modules).

The PowerShell project ships modules for Git, GitHub Copilot CLI, Node.js,
general utilities, declarative setup, Visual Studio, and Windows tooling. This
repository ports the portable workflows to plain bash and provides Linux
equivalents where appropriate.

## Layout

```
bin/          Executable commands (kebab-case, e.g. git-worktree-new)
lib/          Sourceable helper libraries (common.sh + per-area helpers)
completions/  bash and zsh completion for the worktree commands
build/        Lint, public-content scan, and test runner
test/         bats-core test suites
```

## Install

Quick install (clones to `~/.local/share/bash-scripts`, symlinks the commands
into `~/.local/bin`, and wires up completions):

```bash
curl -fsSL https://raw.githubusercontent.com/shmuelie/bash-scripts/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/shmuelie/bash-scripts.git
cd bash-scripts
./install.sh                 # symlink bin/* into ~/.local/bin (default)
./install.sh --method path   # add <repo>/bin to your shell rc instead
./install.sh --update        # git pull, then refresh the install
./install.sh --install-deps  # optionally install missing required dependencies
./install.sh --install-deps --deps all --dry-run
./install.sh --uninstall     # remove whatever the installer added
```

`install.sh` options: `--prefix DIR` (symlink target, default `~/.local/bin`),
`--rc FILE` (shell rc to edit), `--no-completions`, `--update`,
`--install-deps`, `--deps required|all`, `--dry-run`, and `--uninstall`.
Dependency installation is opt-in and uses a detected apt, dnf/yum, pacman,
zypper, or Homebrew package manager. The `required` tier covers bash, git, and
jq; `all` also installs known development/feature packages and reports tools
that require manual installation. Re-running is idempotent, `--update`
fast-forwards the repo and re-links, and `--uninstall` cleanly removes the
symlinks and the rc block. The `curl | bash` bootstrap also updates its clone
automatically each time it runs.

Manual install — just add `bin/` to your `PATH` (the commands self-locate `lib/`,
so you can also symlink individual `bin/*` onto your `PATH`, but never copy them
away from the repo on their own):

```bash
export PATH="/path/to/bash-scripts/bin:$PATH"
```

## Modules

| Area | Status | Focus |
|---|---|---|
| [Git](docs/git.md) | Ported | Worktrees, bulk updates, repo layout, status, multi-account sync, completion |
| [Copilot](docs/copilot.md) | Ported | Copilot CLI launcher, sessions, plugins, marketplaces, MCP |
| [Node](docs/node.md) | Ported | Node/nvm versions, npm packages, Azure DevOps npm credentials |
| [Utilities](docs/utilities.md) | Ported | .NET, Python, VS Code, terminal, services, diagnostics |

Declarative machine setup is available through [`dev-setup`](docs/setup.md) for
symlinks, Copilot plugins/marketplaces, and uv tools.

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
