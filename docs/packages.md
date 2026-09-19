# Aggregate package updates

`package-update` ports the provider-neutral `Shmuelie.PackageManagement` contract.
It selects all integrations by default, skips unavailable dependencies with a
reason, and never installs a missing package manager or SDK.

```bash
package-update --dry-run --json
package-update --provider npm --provider pip --confirm
package-update --exclude-provider vscode --stop-on-failure
package-update --provider uv --options '{"uv":{"scope":"Tools"}}'
package-update --provider vscode --options '{"vscode":{"profiles":["Work"]}}'
package-update --provider psresource --options \
  '{"psresource":{"roots":["/home/me/modules"],"name":["My.*"],"exclude":["*.Local"]}}'
```

Repeat `--provider` and `--exclude-provider`; exclusions win. Provider names are
lowercase. `--options` is a JSON object with only the keys documented below.
All options, including profile names, are validated before native discovery.

| Provider | Selection and options |
|---|---|
| `npm` | Outdated **global** registry packages only; no options. Local dependencies and lockfiles are never selected. Scoped names remain intact. |
| `pip` | Outdated top-level distributions. `user` (default `false`) filters discovery to the user site; `topLevel` (default `true`) controls top-level filtering. |
| `dotnet` | Installed global tools; `name` is an optional wildcard filter. Missing SDK skips. No read-only outdated API is assumed. |
| `uv` | `scope`: `All` (default), `Packages`, or `Tools`. Packages are outdated system distributions; `topLevel` defaults to `true`. Tools use native `uv tool upgrade`, retaining recorded constraints. Tools-only never invokes package helpers. |
| `vscode` | One bulk target for the default profile, plus each distinct name in `profiles` (array). Profiles reject option-like names, controls, path separators, and shell metacharacters. |
| `psresource` | Explicit `roots` array, optional wildcard arrays `name`/`exclude`, and optional `repository` override. No roots means skipped; no ambient resource scan. |

**pip discovery is not installation-destination control.** `user:true` selects
user-installed packages, but the canonical updater still runs `pip install
--upgrade NAME` without `--user`. Its active interpreter/environment and pip
configuration determine the destination. Observation uses the same discovery
scope; if that does not change, the result is Unchanged, not a proposed update.

## Results and approval

`--json` emits one array even when some operations fail. Each result has
`provider`, `target`, `previousVersion`, `proposedVersion`, `resultingVersion`,
`status`, `reason`, and `error`. Unknown versions are `null`, never copied from a
proposed version. Statuses are `Preview`, `Skipped`, `Updated`, `Unchanged`, and
`Failed`. No candidates yields a provider-level Unchanged result; unavailable
integrations/roots yield Skipped results with reasons.

By default, failures do not prevent independent targets/providers from running.
Any failure makes the final exit status nonzero. `--stop-on-failure` stops after
the first failure. Native errors and warnings remain on stderr; update failure
cannot be erased by later unchanged-version observation. Invalid discovery or
missing/ambiguous post-update observations fail instead of claiming success.
An update might already have mutated a target before an observation failure.

`--dry-run`/`--whatif` perform read-only discovery and never call an updater.
Installed .NET tools, uv tools, and PowerShell resources are candidates, not
claims that newer versions exist; their proposed versions remain unknown.
Normal operation approves each target through the shared preview gate.
`--confirm` additionally asks on the controlling terminal for every target;
declining skips that target, and an unavailable terminal fails the approval.

VS Code emits **one bulk result per profile**, with null aggregate versions and
before/after inventories. Updated means the native bulk operation completed with
a fresh zero exit status, not that every extension changed. The bundled canonical
helper supports profiles and propagates native exit codes; the adapter calls it
by repository path, so an older unrelated helper on PATH cannot drop the profile.

## PowerShell-resource integration

Requires optional `pwsh`, `Microsoft.PowerShell.PSResourceGet`, and a compatible
`Shmuelie.Utilities` providing `Update-InstalledPSResource` plus its canonical
`Get-InstalledPSResourceInPath` and `Compare-PSResourceVersion` helpers. Missing
or incompatible integrations skip; no dependency installation is attempted.

The bridge uses only explicitly configured filesystem roots. It delegates
manifest/XML interpretation, prerelease labels, version comparison, repository
provenance, and updates to the canonical module. Bash never infers a stable
version from a numeric directory. Canonical versions therefore preserve stable
promotion and newer prereleases, including metadata recovery behavior supported
by the installed module. Without `repository`, the canonical recorded provenance
is retained. A warning without an observed increase is Skipped; a silent unchanged
version is Unchanged with an explicit explanation that canonical silent skips
cannot be distinguished from already-current resources.

This command covers the six integrations above, not unrelated upstream Windows
package providers. Deterministic tests replace all native package operations;
resource consumer tests use synthetic canonical modules, not live feeds.
