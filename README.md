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
completions/  Bash and zsh completion for all public commands
build/        Lint, public-content scan, and test runner
test/         bats-core test suites
```

## Install

Quick install (clones to `~/.local/share/bash-scripts`, symlinks the commands
into `~/.local/bin`, and wires up completions):

```bash
curl -fsSL https://raw.githubusercontent.com/shmuelie/bash-scripts/main/install.sh | bash
```

To pass installer flags to the quick install, use `bash -s --` followed by the
normal `install.sh` options:

```bash
curl -fsSL https://raw.githubusercontent.com/shmuelie/bash-scripts/main/install.sh \
  | bash -s -- --install-deps --deps all
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
`--rc FILE` (shell rc to edit), `--no-completions`,
`--no-worktree-navigation`, `--update`,
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

## Shell completion

The installer activates [Bash and zsh completion](docs/completions.md) for all
61 public commands, including subcommands, supported flags, enumerated values,
quoted paths, and locally scoped Git/Copilot identifiers. Open a new shell
after installing, or source the configured rc file. Static completion makes no
network calls and never installs dependencies or performs command mutations.

Use `--no-completions` to omit activation or remove an earlier managed
activation on reinstall. For manual setup, source
`completions/bash/shm-git-completion.bash` in Bash, or add `completions/zsh` to
zsh's `fpath` before `compinit`. The completion reference includes exact setup
commands, scope rules, and intentional dynamic-discovery limitations.

## Modules

| Area | Status | Focus |
|---|---|---|
| [Git](docs/git.md) | Ported | Branches, tags, stashes, literal restoration, worktrees, bulk updates, repo layout, status, multi-account sync, completion |
| [Copilot](docs/copilot.md) | Ported | Copilot CLI launcher, filtered sessions, selector callbacks, lossless merges, plugins, marketplaces, MCP |
| [Dev tunnels](docs/devtunnel.md) | Ported | Accounts, tunnel/port/access management, foreground hosting/connections, tokens and diagnostics |
| [Node](docs/node.md) | Ported | Node/nvm versions, npm packages, Azure DevOps npm credentials |
| [Utilities](docs/utilities.md) | Ported | .NET, Python, VS Code, terminal, services, diagnostics |
| [Package updates](docs/packages.md) | Ported | Provider-neutral updates for npm, pip, .NET tools, uv, VS Code, and configured PowerShell resources |

Declarative machine setup is available through [`dev-setup`](docs/setup.md) for
symlinks, Copilot plugins/marketplaces, and uv tools.

[`dotnet-sdk-install`](docs/dotnet-sdk.md) installs verified Microsoft SDKs into
a user-local directory, without changing PATH by default. Package updates and
SDK installation support read-only previews; missing optional integrations are
never installed automatically.

**Worktree removal migration:** `git-worktree-remove` now deletes the backing
local branch after successful removal, including unmerged branches. Use
`--keep-branch` (or legacy `--delete-branch=false`) to retain it, `--dry-run` to
preview both operations, and `--confirm` to approve them separately. Remote
branches are not deleted.

**Interactive navigation migration:** after installing and opening a new
Bash/zsh shell, `git-worktree-new` and `git-worktree-add` enter a successfully
created worktree by default. Use `--stay-in-directory` per invocation, or install
with `--no-worktree-navigation` to disable these wrappers. Executables and
noninteractive scripts still print the target path without changing directory.

## Conventions

- **Commands are kebab-case executables** in `bin/` (e.g. `git-worktree-new`).
- **`--dry-run` / `--whatif`** previews any state-changing command (the bash
  equivalent of PowerShell's `-WhatIf`).
- **`--json`** emits machine-readable output where a command supports it;
  otherwise a human-readable table or summary is printed.
- Executables that would change the shell's directory (like `Set-Location` in
  PowerShell) **print the target path**, so scripts can use them with `cd`.
  The installed interactive wrappers for worktree creation additionally navigate:

  ```bash
  cd "$(git-worktree-switch main)"
  git-worktree-new my-feature                 # interactive: create and enter
  git-worktree-new --stay-in-directory other  # create without entering
  ```

## Requirements

- `bash` 4+, `git`, and `jq`.
- Optional: `fzf` for searchable pickers; Copilot sessions also have a
  descriptive paginated terminal picker.
- `node` for the Copilot session-maintenance subcommands (always present where
  the Copilot CLI runs).
- `python3` and a separately installed Microsoft `devtunnel` 1.0.2115 or
  compatible 1.x for `dev-tunnel`; no helper import or preview runs the CLI.
  Opt-in `./install.sh --install-deps --deps all` maps Python to platform
  packages and reports devtunnel's manual installation instructions.

## Development

```bash
./build/test.sh     # syntax check + shellcheck + public-content scan + bats
./build/lint.sh     # shellcheck only
./build/scan.sh     # public-content policy scan only
```

Requires `shellcheck`, `jq`, and `bats-core`. Complete optional regression
coverage also uses `zsh`, `cc`, `python3`, `tmux`, and `pwsh`. Terminal tests use
private tmux servers and native mocks; PowerShell-resource tests use synthetic
modules without querying package feeds.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
