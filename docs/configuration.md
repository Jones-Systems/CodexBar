---
summary: "CodexBar config file layout for CLI + app settings."
read_when:
  - "Editing the CodexBar config file or moving settings off Keychain."
  - "Adding new provider settings fields or defaults."
  - "Explaining CLI/app configuration and security."
---

# Configuration

CodexBar reads one local JSON file for Codex and Claude provider settings.
API keys, manual cookies, source selection, ordering and token accounts stay
scoped to their provider. Runtime cookie caches and provider OAuth credentials
retain their existing Keychain boundaries.

## Location

- Explicit `CODEXBAR_CONFIG=/absolute/path/config.json` takes precedence.
- Otherwise use an absolute `$XDG_CONFIG_HOME/codexbar/config.json`.
- New installs default to `~/.config/codexbar/config.json`.
- Existing `~/.codexbar/config.json` installs retain that legacy path when no XDG config exists.
- Writes create the directory as needed and apply `0600` file permissions.

## Root shape

```json
{
  "version": 1,
  "providers": [
    {"id": "codex", "enabled": true, "source": "auto"},
    {"id": "claude", "enabled": true, "source": "auto"}
  ]
}
```

Entries for retired provider IDs are skipped before decoding their settings or
credentials. Missing retained providers are appended with defaults during
normalization. Explicit unknown CLI provider selection fails instead of fetching
a different enabled provider. Old `pluginSettings`, `pluginSecrets` and top-level
`hooks` values are ignored and are not written back.

## External event hooks

Hooks and their CLI commands are removed. Persisted hook configuration is inert.
Historical implementation and tests can be restored from Git
`91bd5fb4af704da9181212bea636d527a058e615`; restoration needs new qualification.

## Provider fields

- `id` is required and identifies `codex` or `claude`.
- `enabled` controls persistent provider enablement.
- `source` selects a supported mode: `auto`, `web`, `cli`, `oauth` or `api`.
  Supported modes and fallback order differ by provider; see [providers](providers.md).
- `apiKey` is consumed by Claude Admin API; use an organization key with usage permissions.
- `cookieSource` is `auto`, `manual` or `off`; `cookieHeader` stores a manual HTTP cookie header.
- `tokenAccounts` stores the retained provider's supported token/cookie account choices.
- `extrasEnabled`, `quotaWarnings` and `accentColor` control shared presentation behavior.
- Codex retains its active source, profile-home paths and account-order fields.
- Claude retains its native profile and optional claude-swap configuration.
- Legacy generic fields such as `enterpriseHost`, `region` and `workspaceID` are
  readable; unsupported retained-provider uses are reported by validation.

## Manual cookies

Use manual cookies when automatic browser import is unavailable or disabled.
The app and CLI share the resolved config file. `cookieHeader` expects an HTTP
`Cookie:` header value for the provider origin, not a Netscape cookie export.
Store the header only under that provider's entry and keep the config private.
Set `cookieSource` to `manual` to use it, or `off` to disable cookie imports.

### tokenAccounts

```json
{
  "version": 1,
  "activeIndex": 0,
  "accounts": [
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "label": "Fixture account",
      "token": "fixture-token",
      "addedAt": 1735123456
    }
  ]
}
```

## Provider IDs

See the [generated provider list](provider-ids.md).

## Ordering

The order of `providers` controls app and CLI display order.

## iCloud sync

iCloud synchronization, its settings pane and transport are removed. Legacy sync
switches have no effect. Local fleet/device identity and widget quota snapshots
remain; the previous device ID is read only to preserve that local identity.
The app still observes local config edits through its configuration watcher.

## Notes

Keep the config private: it contains credentials. `codexbar config dump` redacts
supported credential fields by default; `--show-secrets` explicitly reveals them.
Use `codexbar config validate` to inspect errors and warnings with synthetic files
for tests. Source/profile restoration details are in the
[product spec](engineering-specs/slim-codex-claude-product.md).
