# Shell completion

All 61 public commands in `bin/` have Bash and zsh registrations. Completion
uses shared, static command contracts in `lib/completion.sh`, not native help
output. It suggests only supported options for the selected operation; for
example, `copilot-mcp list` offers `--json`, but not `--dry-run` or
`--transport`. Commands without argument interfaces (`is-elevated` and
`reset-terminal`) intentionally return no candidates.

## Installation and activation

The existing installer activates completion by default for either installation
method:

```bash
./install.sh
./install.sh --method path
```

Open a new shell or source the rc file printed by the installer. Bash sources
`completions/bash/shm-git-completion.bash`; its legacy filename is retained,
but it now registers every public command.

For zsh, the installer adds `completions/zsh` to `fpath`, deduplicates that
array, and runs `autoload -Uz compinit; compinit -i -D`. The discoverable
`_shm_commands` autoload file registers all commands, whether completion was
previously initialized or not. `-D` avoids writing a completion dump, and `-i`
ignores insecure completion directories rather than prompting. If completion
is unexpectedly missing, inspect `compaudit` and fix the directory permissions;
do not bypass that check.

The shell is selected by a recognizable `--rc` filename (`*bashrc`, `*.bash`,
`*zshrc`, or `*.zsh`), otherwise by `$SHELL`. Reinstalling replaces the single
managed rc block. `--no-completions` removes any previously installed completion activation
while retaining the selected command installation method and interactive
worktree navigation. `--no-worktree-navigation` independently disables those
wrappers; use both flags to omit both integrations. `--uninstall`
removes the managed rc block and this repository's command symlinks; it leaves
unrelated rc content and symlinks alone. Already-running shells retain their
loaded functions until restarted.

### Manual setup

Bash:

```bash
source /path/to/bash-scripts/completions/bash/shm-git-completion.bash
```

zsh (also suitable before a framework's own `compinit`):

```zsh
typeset -U fpath
fpath=(/path/to/bash-scripts/completions/zsh $fpath)
autoload -Uz compinit
compinit -i -D
```

After initializing zsh completion, the old manual entry point can still be
sourced: `source /path/to/bash-scripts/completions/zsh/shm-git-completion.zsh`.
The commands themselves must be on `PATH`, independently of this manual setup.

## Coverage

Each row includes supported flags and option-value handling in both shells.
`--help`, `--dry-run`/`--whatif`, `--json`, and verbosity flags are offered only
where the command actually accepts them.

| Public commands | Subcommands and specialized completion |
| --- | --- |
| `dev-tunnel` | Nested `user`, `port`, and `access` operations, lifecycle and foreground commands, repeatable labels/ports/scopes, protocol/scope values, and protected token output paths. No CLI discovery or service queries. |
| `git-branch-list`, `git-branch-switch`, `git-branch-remove`, `git-tag-list` | Local/cached remote branch names, tags and configured remotes; switch `--track` uses cached remote branches, while `--create` leaves the new name free-form. |
| `git-worktree-add`, `git-worktree-new`, `git-worktree-list`, `git-worktree-current`, `git-worktree-root`, `git-worktree-path`, `git-worktree-switch`, `git-worktree-remove`, `git-worktree-lock`, `git-worktree-unlock`, `git-worktree-move`, `git-worktree-prune`, `git-worktree-repair`, `git-worktree-update`, `git-worktree-update-all` | Repository/destination directories, worktree branches, branch kind `user`/`feature`/`release`, and legacy deletion Boolean settings. |
| `git-config-set`, `git-stash-save`, `git-stash-restore`, `git-restore`, `git-sync`, `git-stale-branch`, `git-status-summary`, `git-status-segment`, `git-repo-new`, `git-repo-repair` | Config scope `local`/`global`/`system`, existing stash selectors, local source refs, configured remotes, repository directories and literal restore paths. Restore paths are relative to the explicitly selected repository. |
| `copilot-session` | `list`, `select`, `resume`, `rename`, `remove`; session ID values/operands and supported filters. Names and prompts remain free-form. |
| `copilot-session-maintenance` | `repair-events`, `compress`, `merge`; ID operands only, not arbitrary `--keep` numbers. |
| `copilot-mcp`, `copilot-plugin`, `copilot-marketplace` | MCP `list`/`add`/`remove`, transport `stdio`/`http`/`sse`, source `user`/`workspace`/`plugin`/`builtin`; plugin `list`/`install`/`update`/`uninstall`; marketplace `list`/`add`/`remove`/`browse`. MCP `--tools` offers the literal wildcard `*`; empty and comma-separated tool names remain valid free-form values. `--timeout` accepts 1–4294967295 milliseconds without invented numeric suggestions. |
| `start-copilot`, `copilot-launch-plan` | Launcher flags, session resume IDs, selectors, directories and usage-output paths; `--prompt`/`-p`, `--interactive`/`-i`, `--fleet`, `--auto-tier` (`efficiency`, `balance`, `intelligence`), repeatable `--dynamic-retrieval` (`skills=on`, `skills=off`), `--mouse` (`on`, `off`), `--no-mouse`, repeatable `--mcp-github-auth` and `--additional-mcp-config`. JSON stays free-form; `@path` completes files and `@~/path` uses `COPILOT_HOME`. |
| `node-version`, `node-alias`, `nvm-config` | Version `list`/`current`/`available`/`install`/`uninstall`/`use` (`--latest` only for `use`); alias `set`/`remove`/`list`; config `root`/`version`/`installed`/`deactivate`/`node-mirror`/`npm-mirror`. |
| `npm-package`, `pip-package`, `uv-package`, `dotnet-tool`, `uv-tool`, `package-update` | Supported package/tool operations and scopes; pip state `any`/`outdated`/`uptodate`; aggregate providers `npm`/`pip`/`dotnet`/`uv`/`vscode`/`psresource`. |
| `dotnet-sdk-install`, `repair-global-json` | SDK architecture `auto`/`amd64`/`x64`/`x86`/`arm64`/`arm`/`s390x`/`ppc64le`/`riscv64`, quality `daily`/`preview`/`GA`, channel aliases `LTS`/`STS`, and install directories. Numeric versions/channels remain free-form. |
| `vscode-ext`, `start-vscode`, `vscode-chat` | Extension `list`/`install`/`uninstall`/`update`, `.vsix` files, profile/category values, forwarded documented editor flags, editor paths and chat `--add-file` paths. |
| `dev-setup`, `installed-apps`, `ado-npm-token` | Setup `check`/`apply` and JSON config files; application sources `dpkg`/`rpm`/`flatpak`/`snap`; token command's supported options. |
| `perf-record`, `service-process`, `terminal-config`, `format-duration`, `in-location`, `is-elevated`, `reset-terminal` | Recording `start`/`stop` and output files; service/output/format flags; `in-location`'s directory operand. No fabricated service names or no-argument command options. |

Worktree creation includes `--stay-in-directory` to opt out of the interactive
navigation wrappers and `--confirm` for explicit creation approval. Executables
still print paths without changing the parent shell.

Hidden launcher compatibility flags are recognized as input, not promoted as
suggestions. The Windows-only `--no-eager-powershell-resolution` is not offered
on Linux. Native arguments after `--` are not guessed or forwarded to another
completion implementation.

## Safe contextual discovery

- Static subcommands, flags and enum values require no native program, network
  access, help invocation, dependency installation or configuration evaluation.
- Git discovery reads only local refs, remotes, stash selectors and worktree
  inventory. It honors explicit selectors, including selectors after the
  cursor, and never falls back to the caller's repository when a selector fails.
  `-C`/`--repository-path` select the repository; `--path` is a target value
  for worktree switch/remove, a path-addressing switch for lock/unlock/move,
  and a repository selector where supported by other commands.
- Worktree branches use canonical `git-worktree-list --json`, including its
  interpretation of paused-rebase identity. Only `git-worktree-add` excludes
  branches with Git's native `worktreepath` marker. Branch switch/remove do
  not exclude checked-out branches. Worktree names retain case-insensitive
  substring matching.
- Session IDs come exclusively from canonical `copilot-session list --json`.
  Its default repository/branch/moved-worktree scope is authoritative;
  completion does not parse session storage or duplicate identity rules.
  Supported explicit filters are forwarded as literal argv. Global `select`
  uses the list command's `--all`; other operations do not broaden scope.
  Launcher `-C`/`--change-dir` runs discovery in that directory without changing
  the invoking shell. Missing directories, tools, invalid JSON, and failed
  discovery produce no candidates.
- Filenames and directory names preserve spaces and shell quoting. An option
  expecting a value consumes that value even when it resembles another flag.
  `--` ends wrapper-option suggestions; literal path operands continue to
  complete where applicable. Supported attached `--option=value` forms and
  Bash's equals-word breaking are handled without evaluating command lines.
  The ordinary `~/` prefix uses `HOME` without evaluating an expression.
  Zsh uses a literal filesystem prefix rather than expression-expanding
  filesystem helpers; named-directory expressions and arbitrary environment
  expressions are not evaluated. This does not change independent shell
  expansion widgets such as zsh's `expand-or-complete`; the regression driver
  binds TAB to `complete-word` to exercise completion rather than expansion.

Completion deliberately does not query remote version/package catalogs,
source `nvm.sh`, launch selectors, enumerate native plugin/marketplace
inventories, authenticate MCP servers, or discover arbitrary forwarded CLI
options. Model names, profiles, tool names, URLs, JSON, prompts, numeric
settings and other non-enumerable values stay free-form. Missing discovery
results never become example IDs, guessed names or unrelated file candidates.
Line-oriented Bash filename collection does not support filenames containing
embedded newlines.

## Regression tests

`test/completion.bats` checks both shells' candidate output and absence of
native mutations, all-public-command Bash registration/flag behavior, enum
and operation scopes, path/repository distinctions and canonical session
discovery. `test/completion-install.bats` checks both shells' fresh-shell
activation, all-public-command zsh discovery/autoload, installer idempotence,
disable/uninstall and literal installation paths. Its Python PTY driver tests
actual TAB insertion, including quoted paths and the literal tools wildcard,
without executing the completed command.

```bash
bats test/completion.bats test/completion-install.bats test/install.bats
```

The full CI installation includes zsh. When validating with an extracted zsh
distribution, the test-only `SHM_TEST_ZSH_MODULE_PATH` and
`SHM_TEST_ZSH_FUNCTIONS` variables can identify its modules and standard
completion functions; neither is needed for an ordinary installation.
