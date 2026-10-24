---
summary: "CodexBar CLI configuration commands for provider toggles, API keys, and isolated config files."
read_when:
  - Using codexbar config from scripts or CI
  - Enabling or disabling providers without opening Settings
  - Storing provider API keys from the command line
---

# CLI configuration

`codexbar config` edits the same resolved config file used by the app's Settings → Providers pane.
New installs use `~/.config/codexbar/config.json`; absolute `XDG_CONFIG_HOME` paths and `CODEXBAR_CONFIG` are
supported, and existing `~/.codexbar/config.json` installs keep using the legacy file when no XDG config exists.
The CLI writes the file with `0600` permissions.

## Providers

List persistent provider toggles:

```bash
codexbar config providers
codexbar config providers --json --pretty
```

Enable or disable a provider:

```bash
codexbar config enable --provider codex
codexbar config disable --provider claude
```

These are persistent app/CLI settings. They are different from `codexbar usage --provider codex`, which is a one-shot
command override and does not edit config.

If every provider is disabled, `codexbar usage` with no `--provider` prints no text output, and
`codexbar usage --json` prints `[]`. Passing `--provider <name>` still fetches that provider for the one command.

## API keys

API keys are stored under the provider entry in config:

```bash
printf '%s' "$ANTHROPIC_ADMIN_KEY" | codexbar config set-api-key --provider claude --stdin
```

`set-api-key` enables the provider by default. Add `--no-enable` when you only want to save the key:

```bash
printf '%s' "$ANTHROPIC_ADMIN_KEY" | codexbar config set-api-key --provider claude --stdin --no-enable
```

Only Claude consumes a config-backed API key in this product. Claude Admin API
requires an organization key with usage permissions. Codex uses its existing
account/OAuth and CLI sources. Removed provider IDs are rejected by explicit CLI
selection and ignored when reading old persisted provider entries.

## Isolated config files

For tests, demos, and CI, point CodexBar at a temporary config file:

```bash
export CODEXBAR_CONFIG=/tmp/codexbar-config.json
codexbar config enable --provider codex
codexbar config providers --json --pretty
```

The override applies to both reads and writes for the current process environment.

## Cost history window

The app setting controls the menu's local cost-history window. For one-off CLI reports, pass `--days`:

```bash
codexbar cost --provider codex --days 90
codexbar cost --provider claude --days 180 --format json --pretty
```

The accepted range is 1...365 days.

## Validation

After hand-editing config:

```bash
codexbar config validate
codexbar config dump --pretty
```

`dump` prints normalized config, including providers omitted from a hand-written file.
