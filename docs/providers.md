---
summary: "Provider data sources and parsing overview for every registered CodexBar provider."
read_when:
  - Adding or modifying provider fetch/parsing
  - Adjusting provider labels, toggles, or metadata
  - Reviewing data sources for providers
---

# Providers

CodexBar currently registers 2 provider IDs.
The supported IDs are `codex` and `claude`.

This Jones Systems product compiles only Codex and Claude. Other providers,
provider plugins, hooks and iCloud synchronization are removed. Historical
provider guides describe the pre-removal implementation; restore from Git
`91bd5fb4af704da9181212bea636d527a058e615` and qualify it before use.
See the [product spec](engineering-specs/slim-codex-claude-product.md).

## Fetch strategies (current)

Codex and Claude use their existing OAuth, CLI and optional browser sources.
Cookie imports, manual credentials, source selection, ordering and token accounts
remain scoped to the selected provider. Retired config entries are ignored before
decoding their obsolete settings or credentials.

## Usage & Spend settings

Settings → Usage & Spend is a local estimated-cost history page, not a billing receipt and not the menu-bar quota
card. Range choices are 7 / 30 / 90 days and All (the scan window is 365 days). Amounts are list-price equivalents
unless a source also reports plan-metered spend, in which case both columns appear. Day buckets use a pinned IANA
timezone stored when cost tracking is first enabled.

Regular token-history publications also refresh outdated independent Usage & Spend sources, including Claude,
through their own 365-day scan. The dashboard never substitutes the shorter menu history for that scan. Updates
arriving during a scan coalesce into a follow-up; a failed attempt waits for a new token publication or manual
dashboard refresh before retrying. Codex account-cache ownership remains isolated per account.

Native cost-history sources are Codex and Claude. Each native currency has its own total, ranking,
and daily chart; CodexBar never adds or ranks amounts across currencies.

The page also shows token mix (input / output / cache / reasoning), priced/unpriced/unmetered/estimated coverage,
sessions, Codex projects, and a 365-day token heatmap. A heatmap day with no coverage is a gap, not zero activity,
and is not clickable. Custom list-price overlays are documented in `docs/model-pricing.md`.
Cached and combined reports retain token-class details and known request counts. Coverage is combined from each
source's existing classification, so a priced source cannot hide another source's unpriced or unmetered rows.
If coverage totals cannot fit, aggregation falls back to existing request or daily-row inference without changing costs or stored data.

OpenCodex `~/.opencodex/usage.jsonl` is an opt-in, read-only spend source (off by default). It is not a quota
Provider. When both OpenCodex logs and native Codex sessions are present they stay on separate rows; merging would
double-count the same traffic. An optional toggle can hide native Codex while OpenCodex data is present. Export JSON
emits the currently aggregated model (provenance, mix, coverage).

The view stays local and does not upload usage history. Refreshes retain the last successful model if a replacement
scan fails, while provider/account configuration changes replace obsolete results. Coverage text reports how many
days of the selected local calendar window are covered by the scan window; a 30-day selection is not labeled as
complete when the available scan window covers fewer days.

## Codex
- App Auto: OAuth API first; falls back to CLI only when OAuth credentials are missing or auth/refresh is invalid.
- Web dashboard (optional, off by default): `https://chatgpt.com/codex/settings/usage` via WebView + browser cookies.
- Battery saver toggle (currently off by default): reduces routine OpenAI web refreshes but still allows explicit manual refreshes.
- CLI RPC default: `codex ... app-server` JSON-RPC (`account/read`, `account/rateLimits/read`).
- CLI PTY: manual diagnostics/parser coverage only; automatic refresh does not launch bare Codex TUI.
- Local cost usage: scans `CODEX_HOME` (or `~/.codex`) `sessions` and sibling `archived_sessions` JSONL files for the configured history window.
- Completed cost catch-up publishes validated cached history without starting another scan. Native and included Pi/OMP caches must cover the requested window; unavailable or incompatible history preserves existing totals until a later refresh. Token timestamps retain the actual cache scan time. This does not resolve catch-up that remains pending while an active log continuously grows.
- Status: Statuspage.io (OpenAI).
- Details: `docs/codex.md`.


## Claude
- Admin API: `sk-ant-admin...` key in Settings/config, token accounts, or `ANTHROPIC_ADMIN_KEY`.
- Admin API shows organization spend/messages summaries with the same inline dashboard pattern as OpenAI API.
- App Auto: OAuth API (`oauth`) → CLI PTY (`claude`) → Web API (`web`).
- CLI Auto: Web API (`web`) → CLI PTY (`claude`).
- Local cost usage: scans `CLAUDE_CONFIG_DIR` when set, otherwise `~/.config/claude/projects`,
  `~/.claude/projects` (including current Claude Desktop Code/Cowork CLI sessions), and nested Claude Desktop
  local-agent JSONL files for the configured history window.
- Status: Statuspage.io (Anthropic).
- Details: `docs/claude.md`.
