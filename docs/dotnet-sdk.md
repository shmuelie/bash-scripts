# User-local .NET SDK installation

`dotnet-sdk-install` ports `Install-DotNetSdk` from `Shmuelie.DotNet`. It uses
Microsoft's supported dotnet-install script, defaults to `$HOME/.dotnet`, and
never changes PATH or DOTNET_ROOT unless explicitly requested.

```bash
dotnet-sdk-install --version 8.0.412 --json
dotnet-sdk-install --channel 10.0 --quality GA --install-dir "$HOME/sdk-x64"
dotnet-sdk-install --channel LTS --architecture arm64 --install-dir "$HOME/sdk-arm64" --dry-run
```

An exact three-part SDK version may include a prerelease suffix and cannot be
combined with channel/quality. Channel defaults to LTS; STS, numeric `major.minor`,
and .NET 5+ feature-band channels such as `8.0.4xx` are supported. Quality is
`daily`, `preview`, or `GA`, and requires an explicit numeric .NET 5+ channel.
Architecture defaults to the OS architecture; `amd64` aliases `x64`. Different
architectures require separate directories. This installer does not install OS
runtime prerequisites, use sudo, or modify package-manager installations.

## Authenticity and existing-host safety

The script, public key, and detached signature are downloaded only from the
canonical Microsoft HTTPS origin at
`https://builds.dotnet.microsoft.com/dotnet/scripts/v1/`. Redirects and non-200
responses fail rather than following an untrusted URL. GPG verifies the detached
signature using an isolated temporary keyring; the user's GPG state is untouched.
There is no unsigned fallback. `curl`, `gpg`, `jq`, Bash, and GNU-compatible
`readlink`/`od` are required (curl/GPG are unnecessary for preview or exact reuse).

Channel resolution downloads/verifies the installer, invokes its read-only
resolution, and extracts exactly one validated version token. Printed shell
commands are never evaluated. Installation receives discrete arguments including
`--no-path`. Matching SDKs in the selected directory are reused.

An existing host's binary architecture is checked, and
`--skip-non-versioned-files` preserves its unversioned files for **every** SDK
installation. SDK feature-band ordering does not imply bundled runtime or host
ordering. Before success, the selected host must execute that exact SDK's
`dotnet.dll` with `--version`, with isolated CLI state and no ambient `global.json`
selection. An incompatible host fails and requires a separate directory or
explicit host servicing. Installer failures can leave partial SDK files; staging
content is cleaned on success and failure.

## Approval and PATH

`--dry-run`/`--whatif` do not download, stage, install, execute a host, or change
PATH. Download/verification, installation, and process PATH have separate approval
gates. `--confirm` asks separately on the controlling terminal and fails if no
terminal is available. A declined install cannot produce a successful PATH change.

An executable cannot change its parent's environment. `--add-to-process-path`
on the executable affects only that invocation; for an interactive shell, source
the helpers and call the function **directly**, not inside command substitution:

```bash
source /path/to/lib/common.sh
source /path/to/lib/utils/dotnet-sdk.sh
shm_install_dotnet_sdk --version 8.0.412 --add-to-process-path --json
```

The function changes the calling shell's PATH only after verified installation
or reuse, avoids duplicate entries, and leaves DOTNET_ROOT untouched. Unreadable,
unset, or readonly PATH failures stop before installation when detected during
preflight; a PATH-write failure does not emit a success result. There are no
persistent shell-profile changes; `--add-to-user-path` is explicitly unsupported.

JSON reports requested/resolved version and channel, quality, architecture,
installation directory, `Installed`/`AlreadyInstalled`/`Skipped`, and actual
`processPathChanged`/`userPathChanged` booleans. Failure exits nonzero without a
success-shaped result. Preview can know an exact requested version but does not
resolve a channel over the network.
