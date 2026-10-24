# CodexBar 🎚️ — May your tokens never run out.

> Codex and Claude usage, in your menu bar.

This is the [Jones Systems source fork](https://github.com/Jones-Systems/CodexBar) of
[steipete/CodexBar](https://github.com/steipete/CodexBar), a menu bar app for monitoring
AI coding-provider usage, costs, and reset windows.

The release badges, website, and upstream download links below refer to the upstream
project; they do not establish that a downloaded or installed binary contains Jones
Systems changes. For this fork, start with [source development](#build-from-source)
or the [fork guide](docs/FORK_QUICK_START.md). Coding agents start at [AGENTS.md](AGENTS.md).

[![Upstream release](https://img.shields.io/github/v/release/steipete/CodexBar?style=flat-square&color=0a0a0c)](https://github.com/steipete/CodexBar/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0a0a0c?style=flat-square)](https://github.com/steipete/CodexBar/releases/latest)
[![Homebrew](https://img.shields.io/badge/brew-steipete%2Ftap%2Fcodexbar-orange?style=flat-square)](https://github.com/steipete/homebrew-tap)
[![AUR](https://img.shields.io/aur/version/codexbar-cli?style=flat-square&color=1793d1)](https://aur.archlinux.org/packages/codexbar-cli)
[![License: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)
[![Site](https://img.shields.io/badge/site-codexbar.app-16d3b4?style=flat-square)](https://codexbar.app)

Tiny macOS 14+ menu bar app that keeps **Codex and Claude limits visible** and shows when each window resets. One status item per provider, or Merge Icons mode with a provider switcher. No Dock icon, minimal UI, dynamic bar icons.

<img src="docs/codexbar.png" alt="CodexBar menu popover with provider tiles, usage bars, and reset countdowns" width="520" />

## Fork scope

| Area | Source status |
| --- | --- |
| App, shared core, CLI, and widgets | Present in this source tree; platform and provider requirements vary. See the [architecture](docs/architecture.md) and [provider guides](docs/providers.md). |
| Native account controls and observability | Native account/profile controls and independent provider, host, and work observations remain in source. CAAM integration is retired; see the [retirement boundary](docs/engineering-specs/caam-retirement.md). |
| Proposed repository sync safety | [PR #3](https://github.com/Jones-Systems/CodexBar/pull/3) is a separate sync-safety core. |
| Proposed Netdata integration | [PR #4](https://github.com/Jones-Systems/CodexBar/pull/4), [#5](https://github.com/Jones-Systems/CodexBar/pull/5), [#6](https://github.com/Jones-Systems/CodexBar/pull/6), [#7](https://github.com/Jones-Systems/CodexBar/pull/7), and [#8](https://github.com/Jones-Systems/CodexBar/pull/8) form a dependent integration stack. |

The linked proposals are pending work, not integrated or released functionality.
Source integration does not prove release, installation, or live provider availability.
Codex account selection also has distinct effects: `Active` selects usage observation;
`System` promotes the default local auth account. Neither proves that an already-running
Codex process has switched accounts.

## Why

- **Plan around resets.** Per-provider session, weekly, and monthly windows with countdowns to the next reset — stop guessing whether to start that long task.
- **Credits, spend, and cost scans.** Codex credits, Claude Admin API summaries, and local cost scans.
- **Live status.** Provider status polling surfaces incident badges in the menu and an indicator overlay on the bar icon.
- **Provider-specific authentication.** Uses existing sessions, OAuth/device flow,
  API keys, browser cookies, or local files where supported. See
  [configuration](docs/configuration.md) and [Keychain boundaries](docs/keychain-prompts.md).

## Install

The following routes describe upstream distributions and separately maintained packages.
They do not establish a release of this Jones Systems fork. To build this checkout,
use [Build from source](#build-from-source).

### Requirements
- macOS 14+ (Sonoma)

### GitHub Releases
Download: <https://github.com/steipete/CodexBar/releases>

### Homebrew
```bash
brew install --cask codexbar
```

### CLI Tarballs (macOS/Linux)
Homebrew formula (Linux today):
```bash
brew install steipete/tap/codexbar
```
Arch Linux AUR package:
```bash
yay -S codexbar-cli
```
Or download release tarballs from GitHub Releases:
- macOS: `CodexBarCLI-v<tag>-macos-arm64.tar.gz`, `CodexBarCLI-v<tag>-macos-x86_64.tar.gz`
- Linux (glibc): `CodexBarCLI-v<tag>-linux-aarch64.tar.gz`, `CodexBarCLI-v<tag>-linux-x86_64.tar.gz`
- Linux (static musl): `CodexBarCLI-v<tag>-linux-musl-aarch64.tar.gz`, `CodexBarCLI-v<tag>-linux-musl-x86_64.tar.gz`

### First run
- Open Settings → Providers and enable what you use.
- Install/sign in to the provider sources you rely on: CLIs, browser sessions, OAuth/device flow, API keys, local app files, or provider apps depending on the provider.
- Optional: Settings → Providers → Codex → OpenAI cookies (Automatic or Manual) to add dashboard extras.

### Set API keys from the CLI
Provider toggles and API keys live in the resolved CodexBar config file. New installs use
`~/.config/codexbar/config.json`; existing `~/.codexbar/config.json` installs still load from the legacy path. You can
script the same provider list that Settings → Providers uses:

```bash
codexbar config providers
codexbar config enable --provider codex
codexbar config disable --provider claude
```

For API-key providers, store a key without opening Settings:

```bash
printf '%s' "$ANTHROPIC_ADMIN_KEY" | codexbar config set-api-key --provider claude --stdin
```

`set-api-key` trims the piped value, stores it with restrictive config-file permissions, and enables the provider by default. Use `--no-enable` to only save the key, or `--api-key <key>` for one-off local scripts where shell history is not a concern.
See [CLI configuration](docs/cli-configuration.md) for the full flow.

## Providers

This product supports 2 providers: Codex and Claude.

- [Codex](docs/codex.md) — OAuth API or local Codex CLI, plus optional OpenAI web dashboard extras.
- [Claude](docs/claude.md) — OAuth API, browser cookies or CLI fallback; session/weekly quotas and local spend history.

Other providers, provider plugins/QuickJS, hooks and iCloud synchronization are
removed from this product. Source and tests can be restored deliberately from
Git `91bd5fb4af704da9181212bea636d527a058e615`; see the
[product spec](docs/engineering-specs/slim-codex-claude-product.md).

## Icon & Screenshot
The menu bar icon is a tiny usage meter. Bar meaning is provider-specific, and errors/stale data can dim the icon or
show an incident indicator.

## Features
- Multi-provider menu bar with per-provider toggles (Settings → Providers).
- Provider-specific usage meters with reset countdowns.
- Optional Codex web dashboard enrichments (code review remaining, usage breakdown, credits history).
- Inline spend and usage charts for Claude Admin API and retained Codex/Claude local histories.
- Configurable cost-usage scans for Codex + Claude, plus reused chart UI for supported provider histories. Codex history uses a WAL-enabled SQLite store capped at 25,000 retained session entries and 256 MiB.
- A persistent Settings → Usage & Spend view for local 7/30-day estimates, grouped by native currency and limited to providers that expose cost history.
- Provider status polling with incident badges in the menu and icon overlay.
- Merge Icons mode to combine providers into one status item + switcher.
- Display controls for provider icons, labels, bars, reset-time style, and highest-usage auto-selection.
- Fresh installs default to Adaptive refresh. Existing users keep every valid stored choice, while legacy unset or
  invalid preferences resolve to 5 minutes. Manual and fixed 1m, 2m, 5m, 15m, and 30m alternatives remain available.
- Bundled CLI (`codexbar`) for scripts and CI (including `codexbar cost --provider codex`, `claude`, or `both` for local cost usage); macOS and Linux CLI builds available.
- WidgetKit widgets for supported providers.
- Localized app and website with a shared language catalog, automatic website detection,
  persistent pickers, and RTL support.
- Optional session quota notifications and weekly-reset confetti.
- Local parsing for supported files and histories, with provider-specific authentication
  and optional browser-cookie sources.

## Privacy note
Wondering if CodexBar scans your disk? It doesn’t crawl your filesystem; it reads a small set of known locations (browser cookies/local storage, provider config files, local JSONL logs) when the related features are enabled. Plain Adaptive refresh never inspects local agent activity. The separate Adaptive (agent-aware) option asks before inspecting the running-process list (including command lines) to identify Codex/Claude and reading bounded known-session metadata. Declining returns to plain Adaptive. When allowed with Agent Sessions hidden, CodexBar retains only the latest activity time and discards session paths and identities. Provider tokens and token-account settings live in the CodexBar config file with restrictive file permissions. See the discussion and audit notes in [issue #12](https://github.com/steipete/CodexBar/issues/12).

## macOS permissions (why they’re needed)
- **Full Disk Access (optional)**: only required to read Safari cookies/local storage for web-based providers. If you don’t grant it, use another supported browser, manual cookies/API keys, OAuth, or CLI/local sources where that provider supports them.
- **Keychain access (prompted by macOS)**:
  Chromium cookie import needs the browser’s Safe Storage item, and an explicitly enabled Claude OAuth repair may
  read Claude Code’s own Keychain item. Background CodexBar paths fail or skip instead of requesting authorization;
  a user-initiated import or repair can still show the macOS prompt. **Settings → Advanced → Disable Keychain
  access** blocks CodexBar-owned Keychain operations and browser decryption, but cannot constrain provider-owned CLIs
  that CodexBar launches. Manual cookie headers, API keys, and file-backed sources remain alternatives where
  supported. See [Keychain prompts](docs/keychain-prompts.md) for Allow Once vs. Always Allow, recurring grants, and
  safe troubleshooting.
- **Files & Folders prompts (folder/volume access)**: CodexBar launches provider CLIs and local probes for some providers. If those helpers read a project directory or external drive, macOS may ask CodexBar for that folder/volume (e.g., Desktop or an external volume). This is driven by the helper’s working directory, not background disk scanning.
- **What we do not request in the background**: no Screen Recording or Accessibility
  permissions; user-triggered helper actions may ask macOS for Automation permission
  to open Terminal. Authentication and storage depend on the provider; see the
  [provider guides](docs/providers.md).

## Docs
- Providers overview: [docs/providers.md](docs/providers.md)
- Provider authoring: [docs/provider.md](docs/provider.md)
- Issue labeling guide: [docs/ISSUE_LABELING.md](docs/ISSUE_LABELING.md)
- UI & icon notes: [docs/ui.md](docs/ui.md)
- CLI reference: [docs/cli.md](docs/cli.md)
- Configuration: [docs/configuration.md](docs/configuration.md)
- Keychain prompts: [docs/keychain-prompts.md](docs/keychain-prompts.md)
- CLI configuration: [docs/cli-configuration.md](docs/cli-configuration.md)
- Widgets: [docs/widgets.md](docs/widgets.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- Refresh loop: [docs/refresh-loop.md](docs/refresh-loop.md)
- Status polling: [docs/status.md](docs/status.md)
- Sparkle updates: [docs/sparkle.md](docs/sparkle.md)
- Packaging: [docs/packaging.md](docs/packaging.md)
- Development: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- Release checklist: [docs/RELEASING.md](docs/RELEASING.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)

## Build from source

Start with CLI help to build this fork without launching the menu bar app or querying
a provider account.

Prerequisites:

- Git and Swift 6.2 or later; the package declares Swift tools 6.2.
- macOS 14+ for macOS development. Building the app bundle also requires the Xcode
  tooling described in the [development guide](docs/DEVELOPMENT.md).
- On Linux, a supported Swift toolchain and SQLite3/libcurl development libraries
  (for example, `libsqlite3-dev` and `libcurl4-openssl-dev` on Debian/Ubuntu).
  Linux supports shared-core and CLI development, not the macOS app UI.

From a directory where you want the checkout:

```bash
git clone https://github.com/Jones-Systems/CodexBar.git
cd CodexBar
swift build --product CodexBarCLI
swift run --skip-build CodexBarCLI --help
```

The final command prints the CLI command list and exits. Its help path runs before
command descriptors and provider commands; no provider login is needed for this step.
See the [CLI reference](docs/cli.md) for commands and their individual effects.

For changes, follow [AGENTS.md](AGENTS.md) and the
[development verification requirements](docs/DEVELOPMENT.md#verification-and-handoff).
Use [runtime validation and command effects](docs/DEVELOPMENT.md#runtime-validation-and-command-effects)
when app-bundle behavior needs validation: compile/run and launch wrappers terminate
existing processes, and release packaging can launch a copied app.

Installing the CLI from an app bundle is a separate operation.
`bin/install-codexbar-cli.sh` uses the helper in `/Applications/CodexBar.app` and requests
administrator privileges to create or replace command links in `/usr/local/bin` and
`/opt/homebrew/bin`. It is not required for source development; run it only when that
installation and its privileged changes are explicitly intended and authorized.

## Code and interfaces

| Area | Entry point and reference |
| --- | --- |
| Menu bar app and settings | `Sources/CodexBar`; [UI notes](docs/ui.md) |
| Shared provider, configuration, and parsing logic | `Sources/CodexBarCore`; [architecture](docs/architecture.md) and [provider authoring](docs/provider.md) |
| CLI commands | `Sources/CodexBarCLI`; [CLI reference](docs/cli.md) and [CLI configuration](docs/cli-configuration.md) |
| Widgets | `Sources/CodexBarWidget` and `WidgetExtension`; [widget guide](docs/widgets.md) |
| Native and portable tests | `Tests/CodexBarTests` and `TestsLinux`; [development guide](docs/DEVELOPMENT.md) |

For fork-specific orientation, see the [fork quick start](docs/FORK_QUICK_START.md).
For credential prompts, use [Keychain troubleshooting](docs/keychain-prompts.md).
Release destinations, signing, and publication are covered separately in the
[release guide](docs/RELEASING.md).

## Related
- ✂️ [Trimmy](https://github.com/steipete/Trimmy) — “Paste once, run once.” Flatten multi-line shell snippets so they paste and run.
- 🧳 [MCPorter](https://mcporter.dev) — TypeScript toolkit + CLI for Model Context Protocol servers.
- 🧿 [oracle](https://askoracle.dev) — Ask the oracle when you're stuck. Invoke GPT-5 Pro with a custom context and files.

## Looking for a Windows version?
- [Win-CodexBar](https://github.com/Finesssee/Win-CodexBar)

## Linux desktop integration?
- [codexbar-waybar](https://github.com/Marouan-chak/codexbar-waybar) — Waybar custom module + GTK4 popover for Hyprland / Sway / other Wayland compositors, built on top of the bundled Linux CLI.
- [codexbar-cosmic-applet](https://github.com/andrew-verde/codexbar-cosmic-applet) — Native COSMIC (System76) desktop panel applet with a tab per provider, pace projections, and cost/token stats, built on top of the bundled Linux CLI.
- [Codexbar GNOME](https://extensions.gnome.org/extension/9841/codexbar/) — GNOME Shell extension that brings CodexBar usage into the desktop panel.
- [codexbar-cinnamon-applet](https://github.com/jacobcalvert/codexbar-cinnamon-applet) — Linux Mint Cinnamon panel applet powered by CodexBar's JSON output.
- [noctalia-codex-usage](https://github.com/rayoplateado/noctalia-codex-usage) — Noctalia/Quickshell plugin that shows Codex 5-hour and weekly usage limits, built on top of the bundled Linux CLI.
- [KodexBar](https://github.com/tylxr59/KodexBar) — KDE Plasma widget that shows CodexBar usage in the Plasma panel, built on top of the bundled Linux CLI.
- [codexbar-plasmoid](https://github.com/psimaker/codexbar-plasmoid) — KDE Plasma 6 widget for CodexBar's meter icon, provider switcher, quota windows, pace, credits, local cost, and status, powered by the bundled Linux CLI.
- [CodexBar Plasma](https://github.com/Lucenx9/codexbar-plasma) — KDE Plasma 6 widget with multi-provider views, account selection, cost history, notifications, configurable providers, and installable `.plasmoid` releases, powered by the bundled Linux CLI.
- [CodexBar Meter](https://github.com/noctalia-dev/community-plugins/tree/main/codexbar-meter) — Noctalia v5 bar widget and panel showing every enabled provider's quota windows, credits, and pace, installable from Noctalia's plugin store, built on the bundled Linux CLI.

## Status bar & terminal integration
- [showy-quota](https://github.com/enieuwy/showy-quota) — always-on AI plan quota strips for SketchyBar, tmux, and Zellij (standalone WASM plugin), built on `codexbar serve` / the bundled CLI.
- [AI Usage Limits](https://github.com/lenadweb/stream-deck-ai-limits) — Elgato Stream Deck integration for macOS: shows a selected CodexBar provider, account, and configurable quota or payload metrics on keys and Stream Deck+ dials, using local `codexbar serve`.

## Credits
Inspired by [ccusage](https://github.com/ryoppippi/ccusage) (MIT), specifically the cost usage tracking.

## License
MIT • Peter Steinberger ([steipete](https://twitter.com/steipete))
