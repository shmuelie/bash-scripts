# Utilities commands

A bash port of the `Shmuelie.Utilities` PowerShell module. Cross-platform
helpers are ported directly; Windows-only commands are re-implemented with Linux
equivalents. Executables live in `bin/`; a few shell-only helpers are sourceable
from `lib/utils/shell-integration.sh`.

## Commands

| Area | Command |
|---|---|
| Core | `is-elevated`, `in-location`, `repair-global-json`, `reset-terminal`, `format-duration` |
| Shell integration (sourced) | `shm_global_constant`, `shm_path_constant`, `shm_prepend_path`, `shm_session_title`, `shm_source_safe` |
| .NET tools | `dotnet-tool list/install/update/uninstall` |
| Python | `pip-package list/update`, `uv-package list/update`, `uv-tool list/install` |
| VS Code | `start-vscode`, `vscode-chat`, `vscode-ext list/install/uninstall/update` |
| Services | `service-process` (systemd) |
| Diagnostics | `perf-record start/stop` (perf) |
| Inventory | `installed-apps` (dpkg/rpm/flatpak/snap) |
| Terminal | `terminal-config` |

## Cross-platform ports

- `is-elevated` — exits 0 as root (the non-Windows branch of `Test-IsElevated`).
- `in-location` — runs a command in a directory and always returns, even on
  interrupt (`Invoke-InLocation`).
- `repair-global-json` — sets `sdk.rollForward` to `disable` in `./global.json`.
- `reset-terminal` — emits the DEC private-mode and kitty-keyboard reset
  sequence (`Reset-TerminalModes`); no-ops when stdout is redirected.
- `dotnet-tool`, `pip-package`, `uv-package`, `vscode-ext` — tool management
  wrappers with `--json` output and `--dry-run` previews.
- `format-duration` — compact elapsed-time formatting from seconds or
  milliseconds (`H:MM:SS.mmm`, `M:SS.mmm`, or `<seconds> seconds`).
- `pip-package` and `uv-package` extract a complete JSON payload even when the
  underlying tool prints warning lines around it, and fail clearly if none is
  present.

## Shell integration

`New-GlobalConstant`, `New-PathVariable`, `Get-SessionTitle`, and
`Import-ModuleSafe` create shell state, so they are provided as sourceable bash
functions rather than executables:

```bash
source /path/to/lib/utils/shell-integration.sh
shm_global_constant REPO_ROOT "$HOME/src"
shm_prepend_path "$HOME/.local/bin"
```

## Windows-only commands, re-implemented for Linux

| PowerShell | Linux port | Notes |
|---|---|---|
| `Get-ServiceProcess` | `service-process` | Resolves a systemd service to its `MainPID`. |
| `Get-InstalledApplications` | `installed-apps` | Aggregates dpkg, rpm, flatpak, snap. |
| `Start/Stop-WindowsPerformanceRecorder` | `perf-record start/stop` | Wraps `perf record` with a stateful start/stop model. |
| `Get-WindowsTerminalSettings/Profile` | `terminal-config` | Best-effort: Windows Terminal has no Linux equivalent, so this reports the active emulator and its config path. |

## Examples

```bash
is-elevated && echo admin
dotnet-tool list --json | jq -r '.[].packageId'
service-process cron --pid-only | xargs -r kill
installed-apps --source snap
reset-terminal
format-duration --milliseconds 61005
```

## Requirements

- Per-command tools on `PATH`: `dotnet`, `pip`, `uv`, `code`, `systemctl`,
  `perf`, and one of `dpkg`/`rpm`/`flatpak`/`snap`.
- `jq` for `--json` output.
