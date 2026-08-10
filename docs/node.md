# Node commands

A bash port of the `Shmuelie.Node` PowerShell module, re-targeted from
nvm-windows to [nvm.sh](https://github.com/nvm-sh/nvm). Every command is an
executable in `bin/`.

## Commands

| Area | Command |
|---|---|
| Node versions | `node-version list/current/available/install/uninstall/use` |
| Node aliases | `node-alias set/remove/list` |
| nvm control | `nvm-config root/version/installed/deactivate/node-mirror/npm-mirror` |
| npm packages | `npm-package list/update` |
| ADO credentials | `ado-npm-token` |

## nvm.sh vs nvm-windows

The PowerShell module wraps nvm-windows, an executable. `nvm.sh` is a shell
function that must be sourced, so these commands source `"$NVM_DIR/nvm.sh"`
internally. Read, install, uninstall, and alias operations persist to
`$NVM_DIR` and work from a subprocess. **`node-version use` only affects the
invoking process** — a child cannot change your shell's `PATH`. For interactive
use, run `nvm use` directly in your shell.

## Azure DevOps npm token

`ado-npm-token` runs `@microsoft/artifacts-npm-credprovider` against a temporary
`.npmrc` to obtain a fresh token. Because a child process cannot set the parent
shell's environment, it prints an `export` line to evaluate:

```bash
eval "$(ado-npm-token --feed 'https://pkgs.dev.azure.com/org/_packaging/feed/npm/registry/')"
```

Use `--name VAR` to choose a different environment variable (default
`ADO_NPM_TOKEN`). It hardcodes no feed.

## Examples

```bash
node-version install 22.11.0
node-version available | head
npm-package list --global --outdated | ...   # (names) | npm-package update --global
node-alias set default 22.11.0
```

## Requirements

- `nvm.sh` for the version-management commands.
- `npm` and `jq` for `npm-package`.
- `node` and `@microsoft/artifacts-npm-credprovider` for `ado-npm-token`.
