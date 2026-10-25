# Codex and Claude Product

Artifact ID: spec.slim-codex-claude-product
Kind: Engineering Spec
Authority effect: none
Owner: CodexBar product implementation coordinator

<!-- codex-section:begin spec.slim-codex-claude-product#scope -->
## Scope and compatibility

Ship only Codex and Claude provider implementations. Delete other provider source,
provider plugins and their JavaScript engines, hooks, iCloud transport and their
feature-only tests. Git history at `91bd5fb4af704da9181212bea636d527a058e615`
retains the removed implementation for deliberate restoration.

Preserve current usage, quota/reset tracking, account switching and authentication,
provider identity isolation, SPEND/history, local scanning and cache integrity,
shared TTY/process cleanup and cancellation, widgets, and fleet/local identity.
Do not reduce scanner limits or persistence regressions. Persisted configurations
containing removed provider/plugin entries must decode fail-soft, without mapping
their identities or credentials onto Codex or Claude. Obsolete hooks/sync settings
must be inert. No migration reads real credentials or private configuration.
<!-- codex-section:end spec.slim-codex-claude-product#scope -->

<!-- codex-section:begin spec.slim-codex-claude-product#architecture -->
## Source-bound architecture and impact

`Providers/Providers.swift` closes `UsageProvider` to Codex/Claude; both
`ProviderManifest` and the app's `ProviderImplementationManifest` must change with
it because the registry requires metadata for every enum case. Keep shared PTY,
process and cookie capabilities used by these providers regardless of old names.

Remove `CodexBarCore/Plugins`, its bundled JavaScript resources and `CQuickJS`,
then remove their Package.swift target, dependency and JavaScriptCore linkage.
Crypto remains required by managed Codex accounts and CLI authentication;
SweetCookieKit remains required by both retained descriptors. Remove hook command
entry points/config behavior, provider-specific renderer/settings branches and
plugin commands. Preserve unknown JSON extension handling where needed to read
old files safely; do not retain executable plugin behavior.

Remove CloudKit sync transport/coordinator and its app lifecycle wiring. Retain or
relocate shared account/menu/fleet identity models that happen to live in `Sync`.
Source-level architecture changes affect app, core, CLI and widget consumers, so
all applicable platform compiler jobs remain required. The CI sibling authored
compile-once sharding. Root transferred patch01 and then the exact qualified PR40
source plus frozen seven-path patch02 to this coordinator for task-branch integration.
Root retains CI watching, hosted qualification and remote PR merge coordination.

`swift-build-macos` builds/discovers once; both existing shards verify the same-run
artifact and execute only `--skip-build`, with no compilation fallback. Preserve
`ci_swift_test_artifact.py` and `ci_swift_test_native.py` identity, manifest, archive,
native-fingerprint, cleanup and provenance checks. Patch02 removes the obsolete
JSC option/engine wrapper and its four wrapper-only tests; the full-profile test
continues proving discovery, one skipped-build execution and owned cleanup.
The daily 05:00 America/New_York normal-profile schedule, separate concurrency,
producer/shard/aggregate gates and normal/full selector identities remain intact.
Scheduling takes effect only after default-branch integration. The Work Note and
comparison record identify the qualified source, frozen bytes and narrow adaptations.
<!-- codex-section:end spec.slim-codex-claude-product#architecture -->

<!-- codex-section:begin spec.slim-codex-claude-product#verification -->
## Verification and evidence

Remove tests only with deleted product behavior; preserve shared account,
privacy/isolation, quota, cost scanner, persistence and TTY cleanup cases. Update
mixed suites to assert the retained two-provider contract and add synthetic old
config regression coverage. Normal/full membership must reference existing source.

Run `make check` and `make test`; report missing local Swift/formatter tools as
unavailable. Use the shared nonblocking benchmark lock and fresh CPU/RAM admission
before local test starts. Hosted macOS/Linux compilation and isolated tests must
prove the complete source removal. A final focused bulk correctness review checks
removed versus retained behavior. Record source/test counts at the exact base and
candidate revisions. Binary/bundle size and cold-build comparisons require exact,
comparable hosted artifacts; source counts are not size or speed forecasts.
<!-- codex-section:end spec.slim-codex-claude-product#verification -->
