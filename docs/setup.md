# Declarative setup

`dev-setup` checks or applies a versioned JSON description of portable
developer-machine resources. It is idempotent and reuses the existing Copilot
and uv wrappers.

```json
{
  "version": 1,
  "resources": [
    {
      "type": "symlink",
      "path": "/home/me/.gitconfig",
      "target": "/home/me/dotfiles/.gitconfig"
    },
    {
      "type": "copilotPlugin",
      "source": "owner/repository"
    },
    {
      "type": "copilotMarketplace",
      "name": "skills",
      "repository": "owner/marketplace"
    },
    {
      "type": "uvTool",
      "name": "ruff"
    }
  ]
}
```

```bash
dev-setup check setup.json
dev-setup apply setup.json --dry-run
dev-setup apply setup.json --json
```

`check` exits non-zero when any resource is unsatisfied. `apply` continues
after individual failures and reports every resource. Replacing an existing
non-directory path for a symlink requires `--force` or `"force": true` on that
resource; directories are never replaced. URL-sourced Copilot plugins require
an explicit `"name"` for the installed-name presence check.
