# Dev tunnels

`dev-tunnel` is a Bash-facing port of `Shmuelie.DevTunnel`, wrapping Microsoft's
separately installed `devtunnel` CLI. Install it using the
[Microsoft guide](https://learn.microsoft.com/azure/developer/dev-tunnels/get-started)
and put the trusted native executable on `PATH`. Python 3 is required: its
standard library handles process groups, streaming redaction, JSON validation,
timeouts, and secure file creation without shell evaluation or extra packages.
The thin Bash entry point sources `lib/common.sh` and its area helper.

## Supported contract and mapping

This port follows the **1.0.2115** command/flag contract verified by the upstream
[module](https://github.com/shmuelie/powershell-modules/tree/11b9c798b2dba867633872c103c5b5e4abe8f138/modules/Shmuelie.DevTunnel).
It accepts that release and compatible **1.x** versions, rejecting older builds
and new major versions. The CLI is in preview; later compatible versions may
change behavior. The general
[CLI reference](https://learn.microsoft.com/azure/developer/dev-tunnels/cli-commands)
still contains older tags examples: use **labels**, not tags.

| Wrapper command | CLI mapping | Output |
| --- | --- | --- |
| `dev-tunnel version` | `--version` | `{version,path}` JSON |
| `dev-tunnel user login` | `user login` | Streaming text |
| `dev-tunnel user logout/show` | `user logout/show --json` | CLI JSON envelope |
| `dev-tunnel list/show/create/update [ID]` | Same command, `--json` | CLI JSON envelope; `list` has no ID |
| `dev-tunnel delete [ID]` | `delete [ID] --json --force` | CLI JSON envelope |
| `dev-tunnel delete-all` | `delete-all --json --force` | CLI JSON envelope |
| `dev-tunnel host/connect [ID]` | Same command, no `--json` | Streaming text |
| `dev-tunnel port list/show/create/update/delete [ID]` | Same command, `--json` | CLI JSON envelope |
| `dev-tunnel access list/create/delete/reset [ID]` | Same command, `--json` | CLI JSON envelope |
| `dev-tunnel token [ID]` | `token [ID] --json` | Credential-bearing JSON; explicit output policy required |
| `dev-tunnel set ID` / `unset` | Same command, `--json` | CLI JSON envelope |
| `dev-tunnel clusters` / `limits` | Same command, `--json` | CLI JSON envelope |
| `dev-tunnel echo --port N` | `echo http --port=N --interface=127.0.0.1` | Streaming text |
| `dev-tunnel ping URI` | `ping URI` | Streaming text, not a Boolean |

Use `--help` on each command/subcommand for its exact allowed flags. Options
follow the operation (for example, `dev-tunnel user login --dry-run`).
Management JSON is always emitted, even without `--json`, preserving the CLI's
schema and envelope. `--json` is rejected on foreground streams. Empty
management output produces no object; malformed JSON and nonzero CLI exits
are errors. CLI exit statuses are preserved. Management and version calls
close stdin and time out after 60 seconds (`--timeout 1..3600` overrides this).
Foreground commands have no runtime timeout.

IDs are optional except for `set`. Omitted IDs use the CLI's last-used tunnel,
**except `create` and `host`, which create new persistent and temporary tunnels
respectively**. `list` lists; `show` without an ID shows the last-used tunnel.
Selection belongs to the CLI, not this wrapper. Prefer explicit IDs in automation.

Supported options match the CLI names: `--github`, `--use-device-code-auth`,
`--port-number`, `--protocol`, `--description`, `--labels`, `--all-labels`,
`--add-labels`, `--remove-labels`, `--expiration`, `--limit`, `--scopes`,
`--index`, `--organization`, `--repo`, `--anonymous`, `--tenant`, `--deny`,
`--allow-anonymous`, and diagnostic `--ping`, `--size`, `--interval`.
Repeat label/scope flags and host `--port-number` for multiple values; each
value becomes one literal `--option=value` argument, never an evaluated string.
Ports are 1-65535, indices are zero-based, expiration is 1h-720h or 1d-30d,
and scopes are create/manage/manage:ports/host/inspect/connect. Port
show/create/update/delete require `--port-number`; access delete requires
`--index`. Access create requires exactly one subject. Echo defaults to HTTP
and loopback; `--protocol` and IP-valued `--interface` override it. Ping
requires an absolute URI without embedded credentials.

## Safety and output

Sourcing helpers and static Bash/zsh completion do not discover or execute the
CLI, install software, authenticate, or access the service. `--dry-run`/`--whatif`
validates inputs and prints the planned argv without version checks or actions.
Real operations resolve the CLI and invoke `--version` on demand; the CLI
itself may contact its service during this check. Authentication occurs only
through explicit `user login`, using CLI-owned credential storage.

Every delete and access reset requires interactive `y` confirmation. Without
a terminal they fail **before discovery**, unless `--yes` explicitly approves
the operation. `--confirm` requests the same interaction for other operations.
No generic noninteractive auto-yes helper is used. Dry-run never prompts.
CLI `--force` suppresses only its redundant tunnel-deletion prompt after this
wrapper's approval. No arbitrary native argument escape hatch is provided.

Authenticated access remains the default. `--allow-anonymous` on create/host,
or `access create --anonymous` without `--deny`, emits a warning: anyone on
the internet who knows the address can connect. Do not expose an unsafe service.
Service-principal credentials, access-token inputs, and header/certificate
overrides are deliberately not accepted; use the trusted CLI directly for
advanced scenarios.

Token issuance requires either `--output-file PATH` (new mode-0600 file; an
existing file or symlink is rejected) or explicit `--show-token` consent to
write the credential-bearing JSON to stdout. Never publish that output.
Authentication/token failures omit captured output. Streamed text and ordinary
stderr redact known named tokens/secrets, bearer credentials, JWTs, and GitHub
tokens; future arbitrary secret formats cannot be guaranteed. Device-code
instructions intentionally retain the short-lived user code. Avoid recording
login streams, and run only a trusted CLI. Successful non-sensitive management
stderr is surfaced as a warning; errors never replay raw JSON payloads.

## Workflows

Start your local service before hosting:

```bash
dev-tunnel user login --github --use-device-code-auth
dev-tunnel create my-web-tunnel --description 'Local development' --labels web --expiration 1d
dev-tunnel port create my-web-tunnel --port-number 3000 --protocol http
dev-tunnel show my-web-tunnel
dev-tunnel host my-web-tunnel
# Ctrl+C stops hosting; persistent tunnel configuration remains.
dev-tunnel delete my-web-tunnel --dry-run
dev-tunnel delete my-web-tunnel --yes
```

On an authorized client:

```bash
dev-tunnel user login
dev-tunnel connect my-web-tunnel
# Ctrl+C stops local forwarding.
```

Temporary hosting, explicit selection, protected tokens, and diagnostics:

```bash
dev-tunnel host --port-number 3000 --port-number 5000 --protocol http --expiration 1h
dev-tunnel set my-web-tunnel
dev-tunnel show
dev-tunnel access create my-web-tunnel --organization example --scopes connect
dev-tunnel token my-web-tunnel --scopes connect --output-file ./connect-token.json
dev-tunnel unset
dev-tunnel clusters --ping
dev-tunnel limits
dev-tunnel echo --port 8080
# In another terminal:
dev-tunnel ping http://localhost:8080 --size 64 --interval 1000
```

Host, connect, login, echo, and ping run in the foreground and stream useful
output. Ctrl+C or SIGTERM forwards cancellation through cleanup of only the
invocation's owned process group; unrelated CLI instances are never targeted.
Graceful temporary-host shutdown normally deletes its tunnel, but forced
cancellation **does not guarantee service-side deletion**. Set a short expiration
and, if necessary, explicitly delete the recorded temporary ID afterward.
There is no background mode or automatic persistent-resource deletion.

## Offline validation

`bats test/devtunnel.bats` uses an inert fake CLI, including real subprocess
cancellation and timeout probes. Tests never log in, open sockets, create live
tunnels, or expose services. `./build/test.sh` includes this suite.
